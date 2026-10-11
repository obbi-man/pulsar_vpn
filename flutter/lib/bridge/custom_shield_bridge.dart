import 'dart:io';

import 'package:flutter/services.dart';

import 'go_ffi.dart';

/// Cross-platform bridge: Go local proxy (FFI) + OS VPN / system proxy (MethodChannel).
class CustomShieldBridge {
  CustomShieldBridge({MethodChannel? channel, GoFfi? goFfi})
      : _channel = channel ?? const MethodChannel('customshield/vpn'),
        _go = goFfi;

  static const defaultLocalProxyPort = 18080;

  final MethodChannel _channel;
  GoFfi? _go;

  bool _proxyRunning = false;
  bool _systemVpnActive = false;

  bool get isConnected => _proxyRunning && _systemVpnActive;

  GoFfi get _goFfi => _go ??= GoFfi.instance;

  /// Full connect path used by the main Connect button:
  /// 1) Start Go `StartClient` (SOCKS5/HTTP on 127.0.0.1:localProxyPort)
  /// 2) Ask OS to capture all traffic into that local proxy (VPN / system proxy)
  Future<void> connect({
    required String serverIp,
    required int port,
    required String secretKey,
    String connectionId = '',
    int localProxyPort = defaultLocalProxyPort,
  }) async {
    // On Android/Windows/Linux the Go proxy runs in the app process.
    // On iOS/macOS the Network Extension process starts Go itself.
    if (!Platform.isIOS && !Platform.isMacOS) {
      await enableLocalProxy(
        serverIp: serverIp,
        port: port,
        secretKey: secretKey,
        connectionId: connectionId,
        localProxyPort: localProxyPort,
      );
    } else {
      _proxyRunning = true;
    }
    await enableSystemVpn(
      localProxyPort: localProxyPort,
      serverIp: serverIp,
      serverPort: port,
      secretKey: secretKey,
      connectionId: connectionId,
    );
  }

  Future<void> disconnect() async {
    await disableSystemVpn();
    await disableLocalProxy();
  }

  Future<void> enableLocalProxy({
    required String serverIp,
    required int port,
    required String secretKey,
    String connectionId = '',
    int localProxyPort = defaultLocalProxyPort,
  }) async {
    final code = _goFfi.startClient(
      serverIp: serverIp,
      port: port,
      secretKey: secretKey,
      connectionId: connectionId,
      localProxyPort: localProxyPort,
    );
    if (code != 0) {
      throw CustomShieldException(
        'StartClient failed with code $code',
        code: code,
      );
    }
    _proxyRunning = true;
  }

  Future<void> disableLocalProxy() async {
    if (!_proxyRunning) return;
    final code = _goFfi.stopClient();
    _proxyRunning = false;
    if (code != 0 && code != 5) {
      // 5 = not running — acceptable during teardown
      throw CustomShieldException(
        'StopClient failed with code $code',
        code: code,
      );
    }
  }

  /// OS-level capture → local proxy. Android/iOS/macOS: VPN; Windows: system proxy.
  Future<void> enableSystemVpn({
    int localProxyPort = defaultLocalProxyPort,
    String? serverIp,
    int? serverPort,
    String? secretKey,
    String? connectionId,
  }) async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'enableSystemVpn',
        <String, dynamic>{
          'localProxyPort': localProxyPort,
          'proxyHost': '127.0.0.1',
          'mode': Platform.isWindows ? 'system_proxy' : 'vpn',
          // Apple Network Extensions run out-of-process and need these to start Go.
          if (serverIp != null) 'serverIp': serverIp,
          if (serverPort != null) 'serverPort': serverPort,
          if (secretKey != null) 'secretKey': secretKey,
          if (connectionId != null) 'connectionId': connectionId,
        },
      );
      if (result is Map && result['ok'] == false) {
        throw CustomShieldException(
          result['error']?.toString() ?? 'enableSystemVpn failed',
          code: result['code'] is int ? result['code'] as int : null,
          permissionRequired: result['permissionRequired'] == true,
        );
      }
      _systemVpnActive = true;
    } on PlatformException catch (e) {
      throw CustomShieldException(
        e.message ?? e.code,
        code: int.tryParse(e.code),
        permissionRequired: e.code == 'VPN_PERMISSION_REQUIRED',
        details: e.details,
      );
    }
  }

  Future<void> disableSystemVpn() async {
    try {
      await _channel.invokeMethod<dynamic>('disableSystemVpn');
    } on PlatformException catch (e) {
      throw CustomShieldException(e.message ?? e.code, details: e.details);
    } finally {
      _systemVpnActive = false;
    }
  }

  Future<bool> prepareVpnPermission() async {
    if (Platform.isAndroid) {
      final prepared = await _channel.invokeMethod<bool>('prepareVpnPermission');
      return prepared ?? false;
    }
    return true;
  }
}

class CustomShieldException implements Exception {
  CustomShieldException(
    this.message, {
    this.code,
    this.permissionRequired = false,
    this.details,
  });

  final String message;
  final int? code;
  final bool permissionRequired;
  final Object? details;

  @override
  String toString() => 'CustomShieldException($message, code=$code)';
}
