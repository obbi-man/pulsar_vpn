import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/custom_shield_bridge.dart';
import '../models/access_key.dart';
import '../models/connect_ui_state.dart';
import '../widgets/round_connect_button.dart';

/// Client connect screen: round power button + pulsar:// / cs:// access key.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, this.bridge, this.onBack});

  final CustomShieldBridge? bridge;
  final VoidCallback? onBack;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final CustomShieldBridge _bridge =
      widget.bridge ?? CustomShieldBridge();

  final _keyCtrl = TextEditingController();
  ConnectUiState _state = ConnectUiState.disconnected;
  AccessKey? _parsed;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    _keyCtrl.addListener(_onKeyChanged);
  }

  @override
  void dispose() {
    _keyCtrl.removeListener(_onKeyChanged);
    _keyCtrl.dispose();
    super.dispose();
  }

  void _onKeyChanged() {
    final raw = _keyCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _parsed = null;
        _parseError = null;
      });
      return;
    }
    try {
      final key = AccessKey.parse(raw);
      setState(() {
        _parsed = key;
        _parseError = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _parsed = null;
        _parseError = e.message;
      });
    }
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF27272A),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _onRoundButtonPressed() async {
    if (_state == ConnectUiState.connecting) return;

    if (_state == ConnectUiState.connected) {
      setState(() => _state = ConnectUiState.connecting);
      try {
        await _bridge.disconnect();
        if (!mounted) return;
        setState(() => _state = ConnectUiState.disconnected);
      } on CustomShieldException catch (e) {
        if (!mounted) return;
        setState(() => _state = ConnectUiState.disconnected);
        _showErrorSnack(e.message);
      } catch (e) {
        if (!mounted) return;
        setState(() => _state = ConnectUiState.disconnected);
        _showErrorSnack(e.toString());
      }
      return;
    }

    // Disconnected → Connecting
    final key = _parsed;
    if (key == null) {
      _showErrorSnack(
        _parseError ??
            'Вставьте ключ pulsar://… (или cs://) чтобы подключиться',
      );
      return;
    }

    setState(() => _state = ConnectUiState.connecting);
    HapticFeedback.lightImpact();

    try {
      final ready = await _bridge.prepareVpnPermission();
      if (!ready) {
        if (!mounted) return;
        setState(() => _state = ConnectUiState.disconnected);
        _showErrorSnack(
          'Разрешение VPN не выдано. Разрешите Pulsar в системном диалоге и нажмите снова.',
        );
        return;
      }

      await _bridge.connect(
        serverIp: key.serverIp,
        port: key.port,
        secretKey: key.secretKey,
        connectionId: key.connectionId,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _state = ConnectUiState.connected);
    } on CustomShieldException catch (e) {
      if (!mounted) return;
      // Tear down partial proxy if VPN permission failed mid-flight.
      try {
        await _bridge.disconnect();
      } catch (_) {}
      setState(() => _state = ConnectUiState.disconnected);
      _showErrorSnack(
        e.permissionRequired
            ? 'Подключение отменено: нужно разрешение VPN.'
            : e.message,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      try {
        await _bridge.disconnect();
      } catch (_) {}
      setState(() => _state = ConnectUiState.disconnected);
      _showErrorSnack(
        e.code == 'VPN_PERMISSION_REQUIRED'
            ? 'Подключение отменено: нужно разрешение VPN.'
            : (e.message ?? e.code),
      );
    } catch (e) {
      if (!mounted) return;
      try {
        await _bridge.disconnect();
      } catch (_) {}
      setState(() => _state = ConnectUiState.disconnected);
      _showErrorSnack(e.toString());
    }
  }

  String get _statusLabel {
    switch (_state) {
      case ConnectUiState.disconnected:
        return 'Отключено';
      case ConnectUiState.connecting:
        return 'Подключение…';
      case ConnectUiState.connected:
        return 'Подключено';
    }
  }

  String get _hintLabel {
    switch (_state) {
      case ConnectUiState.disconnected:
        return 'Нажмите, чтобы защитить трафик';
      case ConnectUiState.connecting:
        return 'Рукопожатие и туннель';
      case ConnectUiState.connected:
        return 'Трафик идёт через ваш сервер';
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Row(
                children: [
                  if (widget.onBack != null)
                    IconButton(
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: Colors.white70,
                    )
                  else
                    const SizedBox(width: 48),
                  const Expanded(child: _BrandHeader()),
                  const SizedBox(width: 48),
                ],
              ),
              const Spacer(flex: 2),
              Text(
                _statusLabel,
                style: TextStyle(
                  color: _state == ConnectUiState.connected
                      ? const Color(0xFF4ADE80)
                      : Colors.white.withValues(alpha: 0.92),
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _hintLabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 36),
              RoundConnectButton(
                state: _state,
                onPressed: _onRoundButtonPressed,
              ),
              const SizedBox(height: 36),
              _ServerMeta(
                serverIp: parsed?.serverIp,
                connectionId: parsed?.connectionId,
                port: parsed?.port,
                connected: _state == ConnectUiState.connected,
              ),
              const Spacer(flex: 3),
              _AccessKeyField(
                controller: _keyCtrl,
                errorText: _keyCtrl.text.trim().isEmpty ? null : _parseError,
                enabled: _state != ConnectUiState.connecting,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.shield_outlined, color: Colors.white.withValues(alpha: 0.9), size: 22),
        const SizedBox(width: 8),
        Text(
          'Pulsar VPN',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _ServerMeta extends StatelessWidget {
  const _ServerMeta({
    required this.serverIp,
    required this.connectionId,
    required this.port,
    required this.connected,
  });

  final String? serverIp;
  final String? connectionId;
  final int? port;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final ip = serverIp;
    if (ip == null) {
      return Text(
        'Ключ доступа ещё не распознан',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
      );
    }

    final cid = (connectionId == null || connectionId!.isEmpty)
        ? 'авто'
        : connectionId!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          _metaRow(Icons.dns_outlined, 'Сервер', '$ip:${port ?? AccessKey.defaultPort}'),
          const SizedBox(height: 10),
          _metaRow(Icons.fingerprint, 'Connection ID', cid),
          if (connected) ...[
            const SizedBox(height: 10),
            _metaRow(
              Icons.shield,
              'Туннель',
              '127.0.0.1:${CustomShieldBridge.defaultLocalProxyPort}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.4)),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _AccessKeyField extends StatelessWidget {
  const _AccessKeyField({
    required this.controller,
    required this.enabled,
    this.errorText,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ключ доступа',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          maxLines: 2,
          minLines: 1,
          decoration: InputDecoration(
            hintText: 'pulsar://secret@203.0.113.10:51820/?id=aabbccdd',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.04),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFF87171)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFF87171)),
            ),
            errorText: errorText,
            errorMaxLines: 2,
            errorStyle: const TextStyle(color: Color(0xFFF87171), fontSize: 12),
          ),
        ),
      ],
    );
  }
}
