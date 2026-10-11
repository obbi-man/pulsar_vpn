import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/connect_ui_state.dart';

/// Large circular power button — Disconnected / Connecting / Connected.
class RoundConnectButton extends StatefulWidget {
  const RoundConnectButton({
    super.key,
    required this.state,
    required this.onPressed,
  });

  final ConnectUiState state;
  final VoidCallback onPressed;

  @override
  State<RoundConnectButton> createState() => _RoundConnectButtonState();
}

class _RoundConnectButtonState extends State<RoundConnectButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _syncAnim();
  }

  @override
  void didUpdateWidget(covariant RoundConnectButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncAnim();
  }

  void _syncAnim() {
    if (widget.state == ConnectUiState.connecting) {
      _spin.repeat();
    } else {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.state == ConnectUiState.connected;
    final connecting = widget.state == ConnectUiState.connecting;

    final accent = connected
        ? const Color(0xFF4ADE80)
        : connecting
            ? const Color(0xFFA1A1AA)
            : const Color(0xFFE4E4E7);

    return Semantics(
      button: true,
      label: connected
          ? 'Отключить VPN'
          : connecting
              ? 'Подключение'
              : 'Подключить VPN',
      child: GestureDetector(
        onTap: connecting ? null : widget.onPressed,
        child: SizedBox(
          width: 196,
          height: 196,
          child: AnimatedBuilder(
            animation: _spin,
            builder: (context, child) {
              return CustomPaint(
                painter: _RingPainter(
                  progress: connecting ? _spin.value : 1,
                  sweeping: connecting,
                  color: accent,
                  glow: connected,
                ),
                child: child,
              );
            },
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: connected
                        ? const [Color(0xFF14532D), Color(0xFF052E16)]
                        : const [Color(0xFF18181B), Color(0xFF09090B)],
                  ),
                  border: Border.all(
                    color: accent.withValues(alpha: connected ? 0.55 : 0.22),
                    width: 1.5,
                  ),
                  boxShadow: [
                    if (connected)
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 36,
                        spreadRadius: 2,
                      )
                    else
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                  ],
                ),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  size: 64,
                  color: accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.sweeping,
    required this.color,
    required this.glow,
  });

  final double progress;
  final bool sweeping;
  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius, track);

    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: glow ? 0.95 : 0.7);

    if (sweeping) {
      final start = progress * math.pi * 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start - math.pi / 2,
        math.pi * 1.15,
        false,
        active,
      );
    } else {
      canvas.drawCircle(center, radius, active..color = color.withValues(alpha: glow ? 0.65 : 0.28));
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.sweeping != sweeping ||
        oldDelegate.color != color ||
        oldDelegate.glow != glow;
  }
}
