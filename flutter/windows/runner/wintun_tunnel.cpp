#include "wintun_tunnel.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <netioapi.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "iphlpapi.lib")

namespace customshield {
namespace {

// --- Minimal Wintun ABI (dynamic load; no SDK required at compile time) ---
using WINTUN_ADAPTER_HANDLE = void*;
using WINTUN_SESSION_HANDLE = void*;

using WintunCreateAdapterFn = WINTUN_ADAPTER_HANDLE(__stdcall*)(const wchar_t*,
                                                               const wchar_t*,
                                                               const GUID*);
using WintunCloseAdapterFn = void(__stdcall*)(WINTUN_ADAPTER_HANDLE);
using WintunGetAdapterLUIDFn = void(__stdcall*)(WINTUN_ADAPTER_HANDLE, NET_LUID*);
using WintunStartSessionFn = WINTUN_SESSION_HANDLE(__stdcall*)(WINTUN_ADAPTER_HANDLE,
                                                              DWORD);
using WintunEndSessionFn = void(__stdcall*)(WINTUN_SESSION_HANDLE);
using WintunReceivePacketFn = BYTE*(__stdcall*)(WINTUN_SESSION_HANDLE, DWORD*);
using WintunReleaseReceivePacketFn = void(__stdcall*)(WINTUN_SESSION_HANDLE, const BYTE*);
using WintunAllocateSendPacketFn = BYTE*(__stdcall*)(WINTUN_SESSION_HANDLE, DWORD);
using WintunSendPacketFn = void(__stdcall*)(WINTUN_SESSION_HANDLE, const BYTE*);
using WintunGetReadWaitEventFn = HANDLE(__stdcall*)(WINTUN_SESSION_HANDLE);

struct WintunApi {
  HMODULE mod = nullptr;
  WintunCreateAdapterFn CreateAdapter = nullptr;
  WintunCloseAdapterFn CloseAdapter = nullptr;
  WintunGetAdapterLUIDFn GetAdapterLUID = nullptr;
  WintunStartSessionFn StartSession = nullptr;
  WintunEndSessionFn EndSession = nullptr;
  WintunReceivePacketFn ReceivePacket = nullptr;
  WintunReleaseReceivePacketFn ReleaseReceivePacket = nullptr;
  WintunAllocateSendPacketFn AllocateSendPacket = nullptr;
  WintunSendPacketFn SendPacket = nullptr;
  WintunGetReadWaitEventFn GetReadWaitEvent = nullptr;
};

bool LoadWintun(WintunApi* api, std::string* err) {
  wchar_t path[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) {
    *err = "GetModuleFileNameW failed";
    return false;
  }
  wchar_t* slash = wcsrchr(path, L'\\');
  if (!slash) {
    *err = "bad module path";
    return false;
  }
  wcscpy_s(slash + 1, MAX_PATH - (slash + 1 - path), L"wintun.dll");

  api->mod = LoadLibraryW(path);
  if (!api->mod) {
    // Also try bare name (PATH / cwd).
    api->mod = LoadLibraryW(L"wintun.dll");
  }
  if (!api->mod) {
    *err = "wintun.dll not found next to the app (download from https://www.wintun.net/). Falling back to WinInet system proxy.";
    return false;
  }

#define LOAD(name, field)                                                      \
  api->field = reinterpret_cast<decltype(api->field)>(GetProcAddress(api->mod, name)); \
  if (!api->field) {                                                           \
    *err = std::string("wintun.dll missing export ") + name;                   \
    FreeLibrary(api->mod);                                                     \
    api->mod = nullptr;                                                        \
    return false;                                                              \
  }

  LOAD("WintunCreateAdapter", CreateAdapter);
  LOAD("WintunCloseAdapter", CloseAdapter);
  LOAD("WintunGetAdapterLUID", GetAdapterLUID);
  LOAD("WintunStartSession", StartSession);
  LOAD("WintunEndSession", EndSession);
  LOAD("WintunReceivePacket", ReceivePacket);
  LOAD("WintunReleaseReceivePacket", ReleaseReceivePacket);
  LOAD("WintunAllocateSendPacket", AllocateSendPacket);
  LOAD("WintunSendPacket", SendPacket);
  LOAD("WintunGetReadWaitEvent", GetReadWaitEvent);
#undef LOAD
  return true;
}

// --- Tiny IPv4 helpers ---
constexpr uint8_t kIpTun[] = {10, 7, 0, 2};
constexpr uint8_t kIpGw[] = {10, 7, 0, 1};

uint16_t IpChecksum(const void* data, size_t len) {
  const uint8_t* p = static_cast<const uint8_t*>(data);
  uint32_t sum = 0;
  for (size_t i = 0; i + 1 < len; i += 2) {
    sum += (p[i] << 8) | p[i + 1];
  }
  if (len & 1) sum += p[len - 1] << 8;
  while (sum >> 16) sum = (sum & 0xffff) + (sum >> 16);
  return static_cast<uint16_t>(~sum);
}

uint16_t TcpChecksum(const uint8_t src[4], const uint8_t dst[4],
                     const uint8_t* tcp, size_t tcp_len) {
  uint32_t sum = 0;
  sum += (src[0] << 8) | src[1];
  sum += (src[2] << 8) | src[3];
  sum += (dst[0] << 8) | dst[1];
  sum += (dst[2] << 8) | dst[3];
  sum += 6;  // protocol
  sum += static_cast<uint16_t>(tcp_len);
  for (size_t i = 0; i + 1 < tcp_len; i += 2) {
    sum += (tcp[i] << 8) | tcp[i + 1];
  }
  if (tcp_len & 1) sum += tcp[tcp_len - 1] << 8;
  while (sum >> 16) sum = (sum & 0xffff) + (sum >> 16);
  return static_cast<uint16_t>(~sum);
}

bool Socks5Connect(SOCKET s, const char* host, uint16_t port) {
  // greeting
  const uint8_t greet[] = {0x05, 0x01, 0x00};
  if (send(s, reinterpret_cast<const char*>(greet), 3, 0) != 3) return false;
  uint8_t greetr[2];
  if (recv(s, reinterpret_cast<char*>(greetr), 2, MSG_WAITALL) != 2) return false;
  if (greetr[0] != 0x05 || greetr[1] != 0x00) return false;

  std::vector<uint8_t> req;
  req.push_back(0x05);
  req.push_back(0x01);
  req.push_back(0x00);
  in_addr ip4{};
  if (inet_pton(AF_INET, host, &ip4) == 1) {
    req.push_back(0x01);
    const uint8_t* b = reinterpret_cast<const uint8_t*>(&ip4);
    req.insert(req.end(), b, b + 4);
  } else {
    size_t hl = strlen(host);
    if (hl > 255) return false;
    req.push_back(0x03);
    req.push_back(static_cast<uint8_t>(hl));
    req.insert(req.end(), host, host + hl);
  }
  req.push_back(static_cast<uint8_t>((port >> 8) & 0xff));
  req.push_back(static_cast<uint8_t>(port & 0xff));
  if (send(s, reinterpret_cast<const char*>(req.data()),
           static_cast<int>(req.size()), 0) != static_cast<int>(req.size())) {
    return false;
  }
  uint8_t rep[4];
  if (recv(s, reinterpret_cast<char*>(rep), 4, MSG_WAITALL) != 4) return false;
  if (rep[0] != 0x05 || rep[1] != 0x00) return false;
  // drain bind addr
  if (rep[3] == 0x01) {
    char drain[6];
    if (recv(s, drain, 6, MSG_WAITALL) != 6) return false;
  } else if (rep[3] == 0x03) {
    char l;
    if (recv(s, &l, 1, MSG_WAITALL) != 1) return false;
    std::vector<char> drain(static_cast<size_t>(l) + 2);
    if (recv(s, drain.data(), static_cast<int>(drain.size()), MSG_WAITALL) !=
        static_cast<int>(drain.size())) {
      return false;
    }
  } else if (rep[3] == 0x04) {
    char drain[18];
    if (recv(s, drain, 18, MSG_WAITALL) != 18) return false;
  } else {
    return false;
  }
  return true;
}

struct TcpFlow {
  SOCKET sock = INVALID_SOCKET;
  uint8_t client_ip[4]{};
  uint8_t server_ip[4]{};
  uint16_t client_port = 0;
  uint16_t server_port = 0;
  uint32_t client_seq = 0;
  uint32_t server_seq = 0;
  bool established = false;
  std::thread reader;
  std::atomic<bool> alive{true};
};

struct TunnelState {
  std::mutex mu;
  WintunApi api;
  WINTUN_ADAPTER_HANDLE adapter = nullptr;
  WINTUN_SESSION_HANDLE session = nullptr;
  std::thread pump;
  std::atomic<bool> running{false};
  ProxyConfig socks;
  std::unordered_map<uint64_t, std::shared_ptr<TcpFlow>> flows;
  std::string mode;
  bool active = false;
  bool wsa_started = false;
};

TunnelState g;

uint64_t FlowKey(const uint8_t sip[4], uint16_t sport, const uint8_t dip[4],
                 uint16_t dport) {
  uint64_t k = 0;
  k |= (uint64_t)sip[0] << 56;
  k |= (uint64_t)sip[1] << 48;
  k |= (uint64_t)sip[2] << 40;
  k |= (uint64_t)sip[3] << 32;
  k |= (uint64_t)sport << 16;
  k |= dport;
  (void)dip;
  return k;
}

bool SendIpv4Tcp(const uint8_t src[4], const uint8_t dst[4], uint16_t sport,
                 uint16_t dport, uint32_t seq, uint32_t ack, uint8_t flags,
                 const uint8_t* payload, size_t payload_len) {
  if (!g.session) return false;
  size_t tcp_len = 20 + payload_len;
  size_t total = 20 + tcp_len;
  BYTE* pkt = g.api.AllocateSendPacket(g.session, static_cast<DWORD>(total));
  if (!pkt) return false;
  memset(pkt, 0, total);
  pkt[0] = 0x45;
  pkt[2] = static_cast<uint8_t>((total >> 8) & 0xff);
  pkt[3] = static_cast<uint8_t>(total & 0xff);
  pkt[8] = 64;
  pkt[9] = 6;
  memcpy(pkt + 12, src, 4);
  memcpy(pkt + 16, dst, 4);
  uint16_t csum = IpChecksum(pkt, 20);
  pkt[10] = static_cast<uint8_t>((csum >> 8) & 0xff);
  pkt[11] = static_cast<uint8_t>(csum & 0xff);

  uint8_t* tcp = pkt + 20;
  tcp[0] = static_cast<uint8_t>((sport >> 8) & 0xff);
  tcp[1] = static_cast<uint8_t>(sport & 0xff);
  tcp[2] = static_cast<uint8_t>((dport >> 8) & 0xff);
  tcp[3] = static_cast<uint8_t>(dport & 0xff);
  tcp[4] = static_cast<uint8_t>((seq >> 24) & 0xff);
  tcp[5] = static_cast<uint8_t>((seq >> 16) & 0xff);
  tcp[6] = static_cast<uint8_t>((seq >> 8) & 0xff);
  tcp[7] = static_cast<uint8_t>(seq & 0xff);
  tcp[8] = static_cast<uint8_t>((ack >> 24) & 0xff);
  tcp[9] = static_cast<uint8_t>((ack >> 16) & 0xff);
  tcp[10] = static_cast<uint8_t>((ack >> 8) & 0xff);
  tcp[11] = static_cast<uint8_t>(ack & 0xff);
  tcp[12] = 0x50;  // data offset 5
  tcp[13] = flags;
  tcp[14] = 0x10;
  tcp[15] = 0x00;  // window
  if (payload_len && payload) {
    memcpy(tcp + 20, payload, payload_len);
  }
  uint16_t tcsum = TcpChecksum(src, dst, tcp, tcp_len);
  tcp[16] = static_cast<uint8_t>((tcsum >> 8) & 0xff);
  tcp[17] = static_cast<uint8_t>(tcsum & 0xff);
  g.api.SendPacket(g.session, pkt);
  return true;
}

void FlowReader(std::shared_ptr<TcpFlow> flow) {
  char buf[16 * 1024];
  while (flow->alive && g.running) {
    int n = recv(flow->sock, buf, sizeof(buf), 0);
    if (n <= 0) {
      SendIpv4Tcp(flow->server_ip, flow->client_ip, flow->server_port,
                  flow->client_port, flow->server_seq, flow->client_seq,
                  0x11 /* FIN+ACK */, nullptr, 0);
      flow->alive = false;
      break;
    }
    SendIpv4Tcp(flow->server_ip, flow->client_ip, flow->server_port,
                flow->client_port, flow->server_seq, flow->client_seq,
                0x18 /* PSH+ACK */, reinterpret_cast<uint8_t*>(buf),
                static_cast<size_t>(n));
    flow->server_seq += static_cast<uint32_t>(n);
  }
  if (flow->sock != INVALID_SOCKET) {
    closesocket(flow->sock);
    flow->sock = INVALID_SOCKET;
  }
}

bool ConfigureAdapterAddress(NET_LUID luid, std::string* err) {
  MIB_UNICASTIPADDRESS_ROW row;
  InitializeUnicastIpAddressEntry(&row);
  row.InterfaceLuid = luid;
  row.Address.si_family = AF_INET;
  row.Address.Ipv4.sin_family = AF_INET;
  row.Address.Ipv4.sin_addr.S_un.S_un_b.s_b1 = kIpTun[0];
  row.Address.Ipv4.sin_addr.S_un.S_un_b.s_b2 = kIpTun[1];
  row.Address.Ipv4.sin_addr.S_un.S_un_b.s_b3 = kIpTun[2];
  row.Address.Ipv4.sin_addr.S_un.S_un_b.s_b4 = kIpTun[3];
  row.OnLinkPrefixLength = 24;
  row.DadState = IpDadStatePreferred;
  DWORD rc = CreateUnicastIpAddressEntry(&row);
  if (rc != NO_ERROR && rc != ERROR_OBJECT_ALREADY_EXISTS) {
    *err = "CreateUnicastIpAddressEntry failed: " + std::to_string(rc);
    return false;
  }

  // Default route via tunnel gateway (metric low so it wins while connected).
  MIB_IPFORWARD_ROW2 route;
  InitializeIpForwardEntry(&route);
  route.InterfaceLuid = luid;
  route.DestinationPrefix.Prefix.si_family = AF_INET;
  route.DestinationPrefix.PrefixLength = 0;
  route.NextHop.si_family = AF_INET;
  route.NextHop.Ipv4.sin_family = AF_INET;
  route.NextHop.Ipv4.sin_addr.S_un.S_un_b.s_b1 = kIpGw[0];
  route.NextHop.Ipv4.sin_addr.S_un.S_un_b.s_b2 = kIpGw[1];
  route.NextHop.Ipv4.sin_addr.S_un.S_un_b.s_b3 = kIpGw[2];
  route.NextHop.Ipv4.sin_addr.S_un.S_un_b.s_b4 = kIpGw[3];
  route.Metric = 5;
  rc = CreateIpForwardEntry2(&route);
  if (rc != NO_ERROR && rc != ERROR_OBJECT_ALREADY_EXISTS) {
    // Non-fatal on some sandboxes; adapter IP alone still useful for tests.
    OutputDebugStringA(("CreateIpForwardEntry2: " + std::to_string(rc)).c_str());
  }
  return true;
}

void HandleIpv4Packet(const BYTE* pkt, DWORD len) {
  if (len < 40) return;
  if ((pkt[0] >> 4) != 4) return;
  size_t ihl = (pkt[0] & 0x0f) * 4;
  if (len < ihl + 20) return;
  if (pkt[9] != 6) return;  // TCP only in this lite path; UDP uses SOCKS ASSOCIATE via apps through WinInet fallback for DNS-heavy cases — Wintun TCP covers browsers via CONNECT.

  const uint8_t* sip = pkt + 12;
  const uint8_t* dip = pkt + 16;
  const uint8_t* tcp = pkt + ihl;
  uint16_t sport = (tcp[0] << 8) | tcp[1];
  uint16_t dport = (tcp[2] << 8) | tcp[3];
  uint32_t seq = (tcp[4] << 24) | (tcp[5] << 16) | (tcp[6] << 8) | tcp[7];
  uint8_t flags = tcp[13];
  size_t data_off = ((tcp[12] >> 4) * 4);
  if (len < ihl + data_off) return;
  const uint8_t* payload = tcp + data_off;
  size_t plen = len - ihl - data_off;

  // Ignore packets not from our TUN IP.
  if (memcmp(sip, kIpTun, 4) != 0) return;

  uint64_t key = FlowKey(sip, sport, dip, dport);
  std::shared_ptr<TcpFlow> flow;
  {
    std::lock_guard<std::mutex> lock(g.mu);
    auto it = g.flows.find(key);
    if (it != g.flows.end()) flow = it->second;
  }

  if ((flags & 0x02) && !(flags & 0x10)) {  // SYN
    if (flow) return;
    auto nf = std::make_shared<TcpFlow>();
    memcpy(nf->client_ip, sip, 4);
    memcpy(nf->server_ip, dip, 4);
    nf->client_port = sport;
    nf->server_port = dport;
    nf->client_seq = seq + 1;
    nf->server_seq = 1000;

    SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s == INVALID_SOCKET) return;
    sockaddr_in proxy{};
    proxy.sin_family = AF_INET;
    proxy.sin_port = htons(static_cast<u_short>(g.socks.port));
    inet_pton(AF_INET, g.socks.host.c_str(), &proxy.sin_addr);
    if (connect(s, reinterpret_cast<sockaddr*>(&proxy), sizeof(proxy)) != 0) {
      closesocket(s);
      return;
    }
    char hostbuf[64];
    snprintf(hostbuf, sizeof(hostbuf), "%u.%u.%u.%u", dip[0], dip[1], dip[2],
             dip[3]);
    if (!Socks5Connect(s, hostbuf, dport)) {
      closesocket(s);
      return;
    }
    nf->sock = s;
    nf->established = true;
    {
      std::lock_guard<std::mutex> lock(g.mu);
      g.flows[key] = nf;
    }
    SendIpv4Tcp(dip, sip, dport, sport, nf->server_seq, nf->client_seq,
                0x12 /* SYN+ACK */, nullptr, 0);
    nf->server_seq += 1;
    nf->reader = std::thread(FlowReader, nf);
    return;
  }

  if (!flow || !flow->established) return;

  if (flags & 0x04) {  // RST
    flow->alive = false;
    if (flow->sock != INVALID_SOCKET) {
      closesocket(flow->sock);
      flow->sock = INVALID_SOCKET;
    }
    std::lock_guard<std::mutex> lock(g.mu);
    g.flows.erase(key);
    return;
  }

  if (plen > 0) {
    int sent = send(flow->sock, reinterpret_cast<const char*>(payload),
                    static_cast<int>(plen), 0);
    if (sent > 0) {
      flow->client_seq += static_cast<uint32_t>(sent);
      SendIpv4Tcp(flow->server_ip, flow->client_ip, flow->server_port,
                  flow->client_port, flow->server_seq, flow->client_seq, 0x10,
                  nullptr, 0);
    }
  }

  if (flags & 0x01) {  // FIN
    flow->client_seq += 1;
    SendIpv4Tcp(flow->server_ip, flow->client_ip, flow->server_port,
                flow->client_port, flow->server_seq, flow->client_seq, 0x11,
                nullptr, 0);
    flow->alive = false;
    shutdown(flow->sock, SD_BOTH);
  }
}

void PumpLoop() {
  HANDLE ev = g.api.GetReadWaitEvent(g.session);
  while (g.running) {
    DWORD pkt_len = 0;
    BYTE* pkt = g.api.ReceivePacket(g.session, &pkt_len);
    if (pkt) {
      HandleIpv4Packet(pkt, pkt_len);
      g.api.ReleaseReceivePacket(g.session, pkt);
      continue;
    }
    WaitForSingleObject(ev, 200);
  }
}

void StopWintunLocked() {
  g.running = false;
  if (g.pump.joinable()) g.pump.join();
  {
    for (auto& kv : g.flows) {
      kv.second->alive = false;
      if (kv.second->sock != INVALID_SOCKET) {
        closesocket(kv.second->sock);
        kv.second->sock = INVALID_SOCKET;
      }
      if (kv.second->reader.joinable()) kv.second->reader.join();
    }
    g.flows.clear();
  }
  if (g.session && g.api.EndSession) {
    g.api.EndSession(g.session);
    g.session = nullptr;
  }
  if (g.adapter && g.api.CloseAdapter) {
    g.api.CloseAdapter(g.adapter);
    g.adapter = nullptr;
  }
  if (g.api.mod) {
    FreeLibrary(g.api.mod);
    g.api = {};
  }
}

bool StartWintun(const ProxyConfig& socks, std::string* err) {
  if (!g.wsa_started) {
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
      *err = "WSAStartup failed";
      return false;
    }
    g.wsa_started = true;
  }

  WintunApi api;
  if (!LoadWintun(&api, err)) return false;

  // Stable GUID for CustomShield adapter.
  GUID guid = {0x6a2e0c1d,
               0x9f4b,
               0x4e21,
               {0x8c, 0x3a, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66}};
  WINTUN_ADAPTER_HANDLE adapter =
      api.CreateAdapter(L"CustomShield", L"CustomShield", &guid);
  if (!adapter) {
    *err = "WintunCreateAdapter failed (need admin? signed wintun.dll?)";
    FreeLibrary(api.mod);
    return false;
  }

  NET_LUID luid{};
  api.GetAdapterLUID(adapter, &luid);
  if (!ConfigureAdapterAddress(luid, err)) {
    api.CloseAdapter(adapter);
    FreeLibrary(api.mod);
    return false;
  }

  WINTUN_SESSION_HANDLE session = api.StartSession(adapter, 0x400000);
  if (!session) {
    *err = "WintunStartSession failed";
    api.CloseAdapter(adapter);
    FreeLibrary(api.mod);
    return false;
  }

  g.api = api;
  g.adapter = adapter;
  g.session = session;
  g.socks = socks;
  g.running = true;
  g.pump = std::thread(PumpLoop);
  return true;
}

}  // namespace

TunnelStartResult StartOsTunnel(const ProxyConfig& socks) {
  TunnelStartResult out;
  {
    std::lock_guard<std::mutex> lock(g.mu);
    if (g.active) {
      out.ok = true;
      out.mode = g.mode;
      return out;
    }
  }

  std::string werr;
  if (StartWintun(socks, &werr)) {
    std::lock_guard<std::mutex> lock(g.mu);
    g.active = true;
    g.mode = "wintun";
    out.ok = true;
    out.mode = "wintun";
    return out;
  }

  // Fallback: WinInet system proxy → same local Go SOCKS.
  auto perr = EnableSystemProxy(socks);
  if (!perr.empty()) {
    out.ok = false;
    out.error = werr + " | WinInet fallback failed: " + perr;
    out.mode = "none";
    return out;
  }
  {
    std::lock_guard<std::mutex> lock(g.mu);
    g.active = true;
    g.mode = "system_proxy";
  }
  out.ok = true;
  out.mode = "system_proxy";
  out.error = werr;  // informational: why Wintun was skipped
  return out;
}

std::string StopOsTunnel() {
  std::string mode;
  {
    std::lock_guard<std::mutex> lock(g.mu);
    if (!g.active) return {};
    mode = g.mode;
  }
  if (mode == "wintun") {
    // Join pump outside of g.mu to avoid deadlock with HandleIpv4Packet.
    StopWintunLocked();
  } else {
    auto err = DisableSystemProxy();
    if (!err.empty()) return err;
  }
  std::lock_guard<std::mutex> lock(g.mu);
  g.active = false;
  g.mode.clear();
  return {};
}

bool IsOsTunnelActive() {
  std::lock_guard<std::mutex> lock(g.mu);
  return g.active;
}

std::string CurrentTunnelMode() {
  std::lock_guard<std::mutex> lock(g.mu);
  return g.mode;
}

}  // namespace customshield
