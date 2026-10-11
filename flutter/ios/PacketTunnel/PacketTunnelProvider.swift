import NetworkExtension
import Foundation

/// System packet tunnel: routes 0.0.0.0/0 into a userspace socks tunnel aimed at
/// the Go CustomShield local proxy. The Network Extension runs in a separate
/// process — StartClient must be invoked here (linked libcustomshield.a), not
/// only in the Flutter UI process.
class PacketTunnelProvider: NEPacketTunnelProvider {
  private var tunnelDevice: NWUDPSession?
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

    var serverIP = proxyHost
    var serverPort: Int32 = 51820
    var secretKey = ""
    var connectionID = ""
    if let cfg = (protocolConfiguration as? NETunnelProviderProtocol)?
      .providerConfiguration {
      if let p = cfg["proxyPort"] as? Int { localProxyPort = p }
      if let h = cfg["proxyHost"] as? String { proxyHost = h }
      if let v = cfg["serverIp"] as? String, !v.isEmpty { serverIP = v }
      if let v = cfg["serverPort"] as? Int { serverPort = Int32(v) }
      if let v = cfg["secretKey"] as? String { secretKey = v }
      if let v = cfg["connectionId"] as? String { connectionID = v }
    }

    // Start Go client inside the extension so 127.0.0.1 is reachable here.
    let goStarted = GoClientBridge.start(
      serverIP: serverIP,
      port: serverPort,
      secretKey: secretKey,
      connectionID: connectionID,
      localProxyPort: Int32(localProxyPort)
    )
    if goStarted != 0 {
      NSLog("CustomShield Go StartClient returned \(goStarted)")
    }

    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
    let ipv4 = NEIPv4Settings(addresses: ["10.8.0.2"], subnetMasks: ["255.255.255.0"])
    ipv4.includedRoutes = [NEIPv4Route.default()]
    settings.ipv4Settings = ipv4
    settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
    settings.mtu = 8500

    // Proxy traffic through local SOCKS raised by Go.
    let proxy = NEProxySettings()
    proxy.autoProxyConfigurationEnabled = false
    proxy.httpEnabled = true
    proxy.httpServer = NEProxyServer(address: proxyHost, port: localProxyPort)
    proxy.httpsEnabled = true
    proxy.httpsServer = NEProxyServer(address: proxyHost, port: localProxyPort)
    // SOCKS for apps that honor NEProxySettings.proxyAutoConfig / exclude lists.
    proxy.excludeSimpleHostnames = true
    proxy.matchDomains = [""] // apply broadly
    settings.proxySettings = proxy

    setTunnelNetworkSettings(settings) { error in
      if let error = error {
        completionHandler(error)
        return
      }
      self.readPackets()
      completionHandler(nil)
    }
  }

  override func stopTunnel(with reason: NEProviderStopReason,
                           completionHandler: @escaping () -> Void) {
    _ = GoClientBridge.stop()
    completionHandler()
  }

  /// Drain TUN packets. When linked with hev/tun2socks, forward there; otherwise
  /// NEProxySettings handles HTTP(S) and packets may be dropped — document NDK/link step.
  private func readPackets() {
    packetFlow.readPackets { [weak self] packets, protocols in
      guard let self = self else { return }
      // Production: pass `packets` into tun2socks → socks5://proxyHost:localProxyPort.
      // Placeholder keeps the run-loop alive for proxy-settings based capture.
      _ = protocols
      _ = packets
      self.readPackets()
    }
  }
}

/// Swift-facing wrappers around cgo exports from libcustomshield.a.
enum GoClientBridge {
  static func start(
    serverIP: String,
    port: Int32,
    secretKey: String,
    connectionID: String,
    localProxyPort: Int32
  ) -> Int32 {
#if canImport(CustomShieldGo)
    return serverIP.withCString { ip in
      secretKey.withCString { secret in
        connectionID.withCString { conn in
          StartClient(
            UnsafeMutablePointer(mutating: ip),
            port,
            UnsafeMutablePointer(mutating: secret),
            UnsafeMutablePointer(mutating: conn),
            localProxyPort
          )
        }
      }
    }
#else
    // Linked when PacketTunnel target includes libcustomshield.a + bridging header.
    return StartClientOptional(serverIP, port, secretKey, connectionID, localProxyPort)
#endif
  }

  static func stop() -> Int32 {
#if canImport(CustomShieldGo)
    return StopClient()
#else
    return StopClientOptional()
#endif
  }
}

@_silgen_name("StartClient")
func StartClient(
  _ serverIP: UnsafeMutablePointer<CChar>?,
  _ port: Int32,
  _ secretKey: UnsafeMutablePointer<CChar>?,
  _ connectionID: UnsafeMutablePointer<CChar>?,
  _ localProxyPort: Int32
) -> Int32

@_silgen_name("StopClient")
func StopClient() -> Int32

private func StartClientOptional(
  _ serverIP: String,
  _ port: Int32,
  _ secretKey: String,
  _ connectionID: String,
  _ localProxyPort: Int32
) -> Int32 {
  guard !secretKey.isEmpty else { return 2 }
  return serverIP.withCString { ip in
    secretKey.withCString { secret in
      connectionID.withCString { conn in
        StartClient(
          UnsafeMutablePointer(mutating: ip),
          port,
          UnsafeMutablePointer(mutating: secret),
          UnsafeMutablePointer(mutating: conn),
          localProxyPort
        )
      }
    }
  }
}

private func StopClientOptional() -> Int32 {
  return StopClient()
}
