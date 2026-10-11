import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme/pulsar_theme.dart';

/// First screen: admin (BYO-VPS constructor) vs client (connect with key).
class RoleGateScreen extends StatelessWidget {
  const RoleGateScreen({super.key, required this.state});

  final PulsarAppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.1,
            colors: [Color(0xFF1F2937), PulsarColors.bg],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                const Icon(Icons.shield_moon_rounded,
                    size: 56, color: PulsarColors.accent),
                const SizedBox(height: 16),
                const Text(
                  'Pulsar VPN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: PulsarColors.text,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Конструктор VPN на вашем VPS.\nНе продаём доступ — вы поднимаете свой сервер.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: PulsarColors.textMuted,
                  ),
                ),
                const Spacer(flex: 2),
                _ModeCard(
                  icon: Icons.dns_rounded,
                  title: 'Я админ',
                  subtitle: 'Свой VPS · пользователи · ключи pulsar://',
                  onTap: state.chooseAdmin,
                ),
                const SizedBox(height: 12),
                _ModeCard(
                  icon: Icons.power_settings_new_rounded,
                  title: 'У меня есть ключ',
                  subtitle: 'Подключиться по pulsar:// или cs://',
                  onTap: state.chooseClient,
                ),
                const Spacer(),
                Text(
                  'API: ${state.api.baseUrl}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: PulsarColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatefulWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 120),
      child: Material(
        color: PulsarColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: PulsarColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, color: PulsarColors.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: PulsarColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: PulsarColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: PulsarColors.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
