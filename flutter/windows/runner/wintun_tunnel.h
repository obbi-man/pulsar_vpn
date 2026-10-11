#ifndef RUNNER_WINTUN_TUNNEL_H_
#define RUNNER_WINTUN_TUNNEL_H_

#include <string>

#include "system_proxy.h"

namespace customshield {

// Prefer Wintun (wireguard-windows-style) when wintun.dll is next to the exe.
// Falls back to WinInet system proxy if the DLL / driver is missing.
//
// Layout expected on Windows:
//   <app>/customshield.dll   — Go SOCKS (StartClient)
//   <app>/wintun.dll         — from https://www.wintun.net/ (AMD64/ARM64)
//
// Packet path: OS default route → Wintun adapter → userspace tun2socks →
// local Go SOCKS5 (127.0.0.1:port) → CustomShield UDP → VPS → internet.

struct TunnelStartResult {
  bool ok = false;
  // "wintun" | "system_proxy"
  std::string mode;
  std::string error;
};

TunnelStartResult StartOsTunnel(const ProxyConfig& socks);
std::string StopOsTunnel();
bool IsOsTunnelActive();
std::string CurrentTunnelMode();

}  // namespace customshield

#endif  // RUNNER_WINTUN_TUNNEL_H_
