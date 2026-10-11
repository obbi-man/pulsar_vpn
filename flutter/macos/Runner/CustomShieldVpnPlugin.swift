import FlutterMacOS
import NetworkExtension
import Cocoa

/// macOS MethodChannel → NETunnelProviderManager (system VPN profile).
final class CustomShieldVpnPlugin: NSObject, FlutterPlugin {
  static let channelName = "customshield/vpn"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger
    )
    let instance = CustomShieldVpnPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "prepareVpnPermission":
      result(true)
    case "enableSystemVpn":
      let args = call.arguments as? [String: Any] ?? [:]
      let port = args["localProxyPort"] as? Int ?? 18080
      let host = args["proxyHost"] as? String ?? "127.0.0.1"
      enable(host: host, port: port, result: result)
    case "disableSystemVpn":
      disable(result: result)
    case "isVpnActive":
      NETunnelProviderManager.loadAllFromPreferences { managers, _ in
        result(managers?.first?.connection.status == .connected)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func enable(host: String, port: Int, result: @escaping FlutterResult) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error = error {
        result(FlutterError(code: "VPN_LOAD", message: error.localizedDescription, details: nil))
        return
      }
      let mgr = managers?.first ?? NETunnelProviderManager()
      let proto = NETunnelProviderProtocol()
      proto.providerBundleIdentifier = "com.customshield.customshield.PacketTunnel"
      proto.serverAddress = "CustomShield"
      proto.providerConfiguration = [
        "proxyHost": host,
        "proxyPort": port,
      ]
      mgr.protocolConfiguration = proto
      mgr.localizedDescription = "CustomShield"
      mgr.isEnabled = true
      mgr.saveToPreferences { saveError in
        if let saveError = saveError {
          result(
            FlutterError(
              code: "VPN_PERMISSION_REQUIRED",
              message: saveError.localizedDescription,
              details: ["permissionRequired": true]
            )
          )
          return
        }
        mgr.loadFromPreferences { _ in
          do {
            try mgr.connection.startVPNTunnel(options: [
              "proxyHost": host as NSString,
              "proxyPort": String(port) as NSString,
            ])
            result(["ok": true, "platform": "macos"])
          } catch {
            result(FlutterError(code: "VPN_START", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  private func disable(result: @escaping FlutterResult) {
    NETunnelProviderManager.loadAllFromPreferences { managers, _ in
      managers?.first?.connection.stopVPNTunnel()
      result(["ok": true])
    }
  }
}
