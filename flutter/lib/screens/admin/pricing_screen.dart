import 'package:flutter/material.dart';

import '../../api/pulsar_api.dart';
import '../../theme/pulsar_theme.dart';

class AdminPricingScreen extends StatefulWidget {
  const AdminPricingScreen({super.key, required this.api});

  final PulsarApi api;

  @override
  State<AdminPricingScreen> createState() => _AdminPricingScreenState();
}

class _AdminPricingScreenState extends State<AdminPricingScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _message;
  Map<String, dynamic>? _plan;
  String? _pendingSession;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await widget.api.getPlan();
      setState(() => _plan = p);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upgrade() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final res = await widget.api.startCheckout();
      final session = res['sessionId']?.toString();
      setState(() {
        _pendingSession = session;
        _message = res['message']?.toString() ??
            'Mock checkout готов. Подтвердите оплату.';
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final session = _pendingSession;
    if (session == null) return;
    setState(() => _busy = true);
    try {
      final res = await widget.api.confirmCheckout(session);
      setState(() {
        _message = res['message']?.toString() ?? 'Pro активирован';
        _pendingSession = null;
      });
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan?['plan']?.toString() ?? 'free';
    final isPro = plan == 'pro';
    final used = (_plan?['used'] as num?)?.toInt() ?? 0;
    final limit = _plan?['limit'];
    final price = (_plan?['priceRub'] as num?)?.toInt() ?? 990;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        const Text(
          'Тарифы',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: PulsarColors.text,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Free до 20 пользователей на вашем VPS. Pro — без лимита.',
          style: TextStyle(color: PulsarColors.textMuted),
        ),
        if (_loading) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
        ] else ...[
          const SizedBox(height: 12),
          Text(
            'Сейчас: $plan · $used${limit != null ? ' / $limit' : ' / ∞'}',
            style: const TextStyle(color: PulsarColors.textMuted, fontSize: 13),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: PulsarColors.danger)),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: const TextStyle(color: PulsarColors.accent)),
          ],
          const SizedBox(height: 20),
          _PlanCard(
            title: 'Free',
            price: '0 ₽',
            features: const [
              'До 20 пользователей',
              'Один ваш VPS',
              'Obfuscated UDP',
            ],
            cta: isPro ? 'Базовый' : 'Текущий',
            enabled: false,
            onPressed: null,
          ),
          const SizedBox(height: 12),
          _PlanCard(
            title: 'Pro',
            price: '$price ₽/мес',
            features: const [
              'Безлимит пользователей',
              'Несколько серверов',
              'Приоритетная поддержка',
            ],
            cta: isPro
                ? 'Уже Pro'
                : (_busy ? '…' : 'Обновить до Pro'),
            enabled: !isPro && !_busy,
            onPressed: isPro ? null : _upgrade,
            secondaryCta:
                _pendingSession != null ? 'Подтвердить оплату (mock)' : null,
            onSecondary: _pendingSession != null ? _confirm : null,
          ),
        ],
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.features,
    required this.cta,
    required this.enabled,
    required this.onPressed,
    this.secondaryCta,
    this.onSecondary,
  });

  final String title;
  final String price;
  final List<String> features;
  final String cta;
  final bool enabled;
  final VoidCallback? onPressed;
  final String? secondaryCta;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: PulsarColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PulsarColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: PulsarColors.textMuted, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            price,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: PulsarColors.text,
            ),
          ),
          const SizedBox(height: 12),
          ...features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.check_rounded,
                      size: 16, color: PulsarColors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f, style: const TextStyle(fontSize: 14))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: enabled ? onPressed : null,
              style: FilledButton.styleFrom(
                backgroundColor: PulsarColors.text,
                foregroundColor: PulsarColors.bg,
                disabledBackgroundColor: PulsarColors.surfaceElevated,
                disabledForegroundColor: PulsarColors.textDim,
              ),
              child: Text(cta),
            ),
          ),
          if (secondaryCta != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onSecondary,
                child: Text(secondaryCta!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
