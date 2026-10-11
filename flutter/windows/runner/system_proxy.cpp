#include "system_proxy.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <wininet.h>

#include <sstream>
#include <string>

#pragma comment(lib, "wininet.lib")

namespace customshield {
namespace {

constexpr wchar_t kKeyPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";

struct SavedProxy {
  bool valid = false;
  DWORD enable = 0;
  std::wstring server;
};

SavedProxy g_saved;
bool g_active = false;

bool WriteDword(HKEY key, const wchar_t* name, DWORD value) {
  return RegSetValueExW(key, name, 0, REG_DWORD,
                        reinterpret_cast<const BYTE*>(&value),
                        sizeof(value)) == ERROR_SUCCESS;
}

bool WriteString(HKEY key, const wchar_t* name, const std::wstring& value) {
  return RegSetValueExW(key, name, 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(value.c_str()),
                        static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) ==
         ERROR_SUCCESS;
}

bool ReadDword(HKEY key, const wchar_t* name, DWORD* out) {
  DWORD type = 0;
  DWORD size = sizeof(DWORD);
  return RegQueryValueExW(key, name, nullptr, &type,
                          reinterpret_cast<LPBYTE>(out), &size) == ERROR_SUCCESS &&
         type == REG_DWORD;
}

bool ReadString(HKEY key, const wchar_t* name, std::wstring* out) {
  DWORD type = 0;
  DWORD size = 0;
  if (RegQueryValueExW(key, name, nullptr, &type, nullptr, &size) != ERROR_SUCCESS ||
      type != REG_SZ) {
    return false;
  }
  out->assign(size / sizeof(wchar_t), L'\0');
  if (RegQueryValueExW(key, name, nullptr, &type,
                       reinterpret_cast<LPBYTE>(out->data()), &size) !=
      ERROR_SUCCESS) {
    return false;
  }
  while (!out->empty() && out->back() == L'\0') {
    out->pop_back();
  }
  return true;
}

void NotifyProxyChanged() {
  InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
}

}  // namespace

std::string EnableSystemProxy(const ProxyConfig& cfg) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kKeyPath, 0, KEY_READ | KEY_WRITE, &key) !=
      ERROR_SUCCESS) {
    return "Failed to open Internet Settings registry key";
  }

  SavedProxy saved;
  saved.valid = true;
  ReadDword(key, L"ProxyEnable", &saved.enable);
  ReadString(key, L"ProxyServer", &saved.server);
  g_saved = saved;

  // HTTP CONNECT for WinInet + socks= for apps that honor SOCKS in ProxyServer.
  std::wstringstream ss;
  ss << cfg.host.c_str() << L":" << cfg.port << L";socks=" << cfg.host.c_str()
     << L":" << cfg.port;
  // cfg.host is UTF-8 ascii (127.0.0.1) — widen simply.
  std::wstring host_w(cfg.host.begin(), cfg.host.end());
  std::wstring server =
      host_w + L":" + std::to_wstring(cfg.port) + L";socks=" + host_w + L":" +
      std::to_wstring(cfg.port);

  if (!WriteDword(key, L"ProxyEnable", 1) || !WriteString(key, L"ProxyServer", server)) {
    RegCloseKey(key);
    return "Failed to write ProxyEnable/ProxyServer";
  }
  // Bypass local addresses so the Go proxy itself is reachable.
  WriteString(key, L"ProxyOverride", L"localhost;127.*;<local>");

  RegCloseKey(key);
  NotifyProxyChanged();
  g_active = true;
  (void)ss;
  return {};
}

std::string DisableSystemProxy() {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kKeyPath, 0, KEY_WRITE, &key) !=
      ERROR_SUCCESS) {
    return "Failed to open Internet Settings registry key";
  }

  if (g_saved.valid) {
    WriteDword(key, L"ProxyEnable", g_saved.enable);
    WriteString(key, L"ProxyServer", g_saved.server);
  } else {
    WriteDword(key, L"ProxyEnable", 0);
  }

  RegCloseKey(key);
  NotifyProxyChanged();
  g_active = false;
  g_saved = {};
  return {};
}

bool IsSystemProxyActive() { return g_active; }

}  // namespace customshield
