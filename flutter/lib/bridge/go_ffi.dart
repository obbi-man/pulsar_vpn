import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _StartClientC = Int32 Function(
  Pointer<Utf8> serverIp,
  Int32 port,
  Pointer<Utf8> secretKey,
  Pointer<Utf8> connectionId,
  Int32 localProxyPort,
);
typedef _StartClientDart = int Function(
  Pointer<Utf8> serverIp,
  int port,
  Pointer<Utf8> secretKey,
  Pointer<Utf8> connectionId,
  int localProxyPort,
);

typedef _StopClientC = Int32 Function();
typedef _StopClientDart = int Function();

/// Thin Dart FFI wrapper around the Go c-shared library (`StartClient` / `StopClient`).
/// Does not invent a second protocol — uses the existing CustomShield UDP client.
class GoFfi {
  GoFfi._(this._start, this._stop);

  final _StartClientDart _start;
  final _StopClientDart _stop;

  static GoFfi? _instance;

  static GoFfi get instance {
    final existing = _instance;
    if (existing != null) return existing;
    final lib = _openLib();
    final start = lib
        .lookupFunction<_StartClientC, _StartClientDart>('StartClient');
    final stop =
        lib.lookupFunction<_StopClientC, _StopClientDart>('StopClient');
    return _instance = GoFfi._(start, stop);
  }

  static DynamicLibrary _openLib() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libcustomshield.so');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('customshield.dll');
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libcustomshield.so');
    }
    throw UnsupportedError('Unsupported platform for Go FFI');
  }

  /// Starts the local SOCKS5/HTTP proxy via the Go client.
  /// Returns 0 on success (see custom-protocol/client.go constants).
  int startClient({
    required String serverIp,
    required int port,
    required String secretKey,
    String connectionId = '',
    int localProxyPort = 18080,
  }) {
    final ipPtr = serverIp.toNativeUtf8();
    final secretPtr = secretKey.toNativeUtf8();
    final connPtr = connectionId.toNativeUtf8();
    try {
      return _start(ipPtr, port, secretPtr, connPtr, localProxyPort);
    } finally {
      malloc.free(ipPtr);
      malloc.free(secretPtr);
      malloc.free(connPtr);
    }
  }

  int stopClient() => _stop();
}
