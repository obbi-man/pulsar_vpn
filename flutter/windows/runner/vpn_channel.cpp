#include "vpn_channel.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "system_proxy.h"
#include "wintun_tunnel.h"

namespace {

class VpnChannel {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto channel =
        std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "customshield/vpn",
            &flutter::StandardMethodCodec::GetInstance());

    channel->SetMethodCallHandler(
        [channel](const auto& call, auto result) {
          HandleMethodCall(call, std::move(result));
        });
  }

 private:
  static void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() == "prepareVpnPermission") {
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (call.method_name() == "enableSystemVpn") {
      customshield::ProxyConfig cfg;
      if (const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments())) {
        auto port_it = args->find(flutter::EncodableValue("localProxyPort"));
        if (port_it != args->end()) {
          if (const auto* p = std::get_if<int>(&port_it->second)) {
            cfg.port = *p;
          }
        }
        auto host_it = args->find(flutter::EncodableValue("proxyHost"));
        if (host_it != args->end()) {
          if (const auto* h = std::get_if<std::string>(&host_it->second)) {
            cfg.host = *h;
          }
        }
      }
      auto started = customshield::StartOsTunnel(cfg);
      if (!started.ok) {
        result->Error("TUNNEL_ENABLE", started.error);
        return;
      }
      flutter::EncodableMap ok;
      ok[flutter::EncodableValue("ok")] = flutter::EncodableValue(true);
      ok[flutter::EncodableValue("platform")] =
          flutter::EncodableValue("windows");
      ok[flutter::EncodableValue("mode")] =
          flutter::EncodableValue(started.mode);
      if (!started.error.empty()) {
        ok[flutter::EncodableValue("fallbackReason")] =
            flutter::EncodableValue(started.error);
      }
      result->Success(flutter::EncodableValue(ok));
      return;
    }
    if (call.method_name() == "disableSystemVpn") {
      auto err = customshield::StopOsTunnel();
      if (!err.empty()) {
        result->Error("TUNNEL_DISABLE", err);
        return;
      }
      flutter::EncodableMap ok;
      ok[flutter::EncodableValue("ok")] = flutter::EncodableValue(true);
      result->Success(flutter::EncodableValue(ok));
      return;
    }
    if (call.method_name() == "isVpnActive") {
      result->Success(
          flutter::EncodableValue(customshield::IsOsTunnelActive()));
      return;
    }
    result->NotImplemented();
  }
};

}  // namespace

void RegisterCustomShieldVpnChannel(flutter::PluginRegistrarWindows* registrar) {
  VpnChannel::RegisterWithRegistrar(registrar);
}
