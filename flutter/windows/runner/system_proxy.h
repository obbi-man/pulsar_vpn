#ifndef RUNNER_SYSTEM_PROXY_H_
#define RUNNER_SYSTEM_PROXY_H_

#include <string>

// WinInet system proxy fallback (registry + InternetSetOption).
// Preferred path is Wintun — see wintun_tunnel.h / flutter/README.md.
namespace customshield {

struct ProxyConfig {
  std::string host = "127.0.0.1";
  int port = 18080;
};

// Enables HKCU Internet Settings proxy to host:port (HTTP + SOCKS form).
// Returns empty string on success, or an error message.
std::string EnableSystemProxy(const ProxyConfig& cfg);

// Restores prior ProxyEnable / ProxyServer values captured on enable.
std::string DisableSystemProxy();

bool IsSystemProxyActive();

}  // namespace customshield

#endif  // RUNNER_SYSTEM_PROXY_H_
