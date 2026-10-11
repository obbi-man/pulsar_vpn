import 'package:flutter/material.dart';

import '../../api/pulsar_api.dart';
import '../../theme/pulsar_theme.dart';

class AdminServerScreen extends StatefulWidget {
  const AdminServerScreen({super.key, required this.api});

  final PulsarApi api;

  @override
  State<AdminServerScreen> createState() => _AdminServerScreenState();
}

class _AdminServerScreenState extends State<AdminServerScreen> {
  final _ip = TextEditingController();
  final _login = TextEditingController(text: 'root');
  final _password = TextEditingController();
  final _port = TextEditingController(text: '22');

  int _step = 0; // 0 idle, 1 ssh, 2 docker, 3 protocol, 4 done
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _ip.dispose();
    _login.dispose();
    _password.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _runSetup() async {
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
      _step = 1;
    });

    // Optimistic progress while API runs SSH deploy.
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && _busy && _step < 2) setState(() => _step = 2);
    });
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted && _busy && _step < 3) setState(() => _step = 3);
    });

    try {
      final res = await widget.api.setupServer(
        ip: _ip.text.trim(),
        password: _password.text,
        login: _login.text.trim().isEmpty ? 'root' : _login.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 22,
      );
      if (!mounted) return;
      setState(() {
        _step = 4;
        _success = res['message']?.toString() ?? 'Pulsar развёрнут на VPS';
      });
    } on PulsarApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _step = 0;
        _error = e.details == null ? e.message : '${e.message}\n${e.details}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = 0;
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _step == 0 ? 0.0 : (_step.clamp(1, 4) / 4);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        const Text(
          'Ваш VPS',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: PulsarColors.text,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ubuntu 22.04 · IP и пароль. Pulsar поднимет протокол на сервере.',
          style: TextStyle(color: PulsarColors.textMuted, height: 1.35),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _ip,
          decoration: const InputDecoration(
            labelText: 'IP адрес',
            hintText: '203.0.113.10',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _login,
                decoration: const InputDecoration(labelText: 'Логин'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'SSH порт'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Пароль SSH'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy || _ip.text.trim().isEmpty ? null : _runSetup,
          style: FilledButton.styleFrom(
            backgroundColor: PulsarColors.text,
            foregroundColor: PulsarColors.bg,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(_busy ? 'Развёртывание…' : 'Установить Pulsar'),
        ),
        if (_step > 0) ...[
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _busy ? null : progress,
              minHeight: 6,
              backgroundColor: PulsarColors.surfaceElevated,
              color: PulsarColors.accent,
            ),
          ),
          const SizedBox(height: 14),
          _StepRow(done: _step >= 1, active: _step == 1, label: '1. SSH'),
          _StepRow(done: _step >= 2, active: _step == 2, label: '2. Docker'),
          _StepRow(
            done: _step >= 3,
            active: _step == 3,
            label: '3. Pulsar протокол',
          ),
          _StepRow(done: _step >= 4, active: _step == 4, label: '4. Готово'),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          _Banner(text: _error!, color: PulsarColors.danger),
        ],
        if (_success != null) ...[
          const SizedBox(height: 16),
          _Banner(text: _success!, color: PulsarColors.accent),
        ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.done,
    required this.active,
    required this.label,
  });

  final bool done;
  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? PulsarColors.accent
        : active
            ? PulsarColors.text
            : PulsarColors.textDim;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(text, style: TextStyle(color: color, height: 1.35)),
    );
  }
}
