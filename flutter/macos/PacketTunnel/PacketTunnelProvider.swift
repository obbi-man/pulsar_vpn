import NetworkExtension
import Foundation

/// macOS packet tunnel — mirrors iOS: 0.0.0.0/0 + local Go SOCKS/HTTP proxy.
class PacketTunnelProvider: NEPacketTunnelProvider {
  private var localProxyPort: Int = 18080
  private var proxyHost: String = "127.0.0.1"

  override func startTunnel(options: [String: NSObject]?,
                            completionHandler: @escaping (Error?) -> Void) {
    if let portStr = options?["proxyPort"] as? String, let p = Int(portStr) {
      localProxyPort = p
    }
    if let host = options?["proxyHost"] as? String {
      proxyHost = host
    }

    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
    let ipv4 = NEIPv4Settings(addresses: ["10.8.0.2"], subnetMasks: ["255.255.255.0"])
    ipv4.includedRoutes = [NEIPv4Route.default()]
    settings.ipv4Settings = ipv4
    settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
    settings.mtu = 8500

    let proxy = NEProxySettings()
    proxy.httpEnabled = true
    proxy.httpServer = NEProxyServer(address: proxyHost, port: localProxyPort)
    proxy.httpsEnabled = true
    proxy.httpsServer = NEProxyServer(address: proxyHost, port: localProxyPort)
    proxy.matchDomains = [""]
    settings.proxySettings = proxy

    setTunnelNetworkSettings(settings) { error in
      completionHandler(error)
    }
  }

  override func stopTunnel(with reason: NEProviderStopReason,
                           completionHandler: @escaping () -> Void) {
    completionHandler()
  }
}
