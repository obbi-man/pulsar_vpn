import Flutter
import NetworkExtension
import UIKit

/// MethodChannel bridge for iOS system VPN (NETunnelProviderManager).
final class CustomShieldVpnPlugin: NSObject, FlutterPlugin {
  static let channelName = "customshield/vpn"

  private var manager: NETunnelProviderManager?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = CustomShieldVpnPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "prepareVpnPermission":
      // iOS prompts when the configuration is saved / started.
      result(true)
    case "enableSystemVpn":
      let args = call.arguments as? [String: Any] ?? [:]
      let port = args["localProxyPort"] as? Int ?? 18080
      let host = args["proxyHost"] as? String ?? "127.0.0.1"
      enable(args: args, host: host, port: port, result: result)
    case "disableSystemVpn":
      disable(result: result)
    case "isVpnActive":
      result(manager?.connection.status == .connected)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func enable(
    args: [String: Any],
    host: String,
    port: Int,
    result: @escaping FlutterResult
  ) {
    NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
      if let error = error {
        result(FlutterError(code: "VPN_LOAD", message: error.localizedDescription, details: nil))
        return
      }
      let mgr = managers?.first ?? NETunnelProviderManager()
      self?.manager = mgr

      let proto = NETunnelProviderProtocol()
      // Bundle id of the PacketTunnel extension — must match Xcode target.
      proto.providerBundleIdentifier = "com.customshield.customshield.PacketTunnel"
      proto.serverAddress = "CustomShield"
      proto.providerConfiguration = [
        "proxyHost": host,
        "proxyPort": port,
        "serverIp": args["serverIp"] as? String ?? "",
        "serverPort": args["serverPort"] as? Int ?? 51820,
        "secretKey": args["secretKey"] as? String ?? "",
        "connectionId": args["connectionId"] as? String ?? "",
        "startGoInExtension": true,
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
            result(["ok": true, "platform": "ios"])
          } catch {
            result(
              FlutterError(
                code: "VPN_START",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
        }
      }
    }
  }

  private func disable(result: @escaping FlutterResult) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error = error {
        result(FlutterError(code: "VPN_LOAD", message: error.localizedDescription, details: nil))
        return
      }
      guard let mgr = managers?.first else {
        result(["ok": true])
        return
      }
      mgr.connection.stopVPNTunnel()
      result(["ok": true])
    }
  }
}
