import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../theme/pulsar_theme.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key, required this.state});

  final PulsarAppState state;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _email = TextEditingController(text: 'admin@pulsar.local');
  final _password = TextEditingController(text: 'demo-admin');
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Accept both new and legacy demo emails.
      var email = _email.text.trim();
      if (email == 'admin@customshield.local') {
        email = 'admin@pulsar.local';
      }
      await widget.state.demoLogin(email, _password.text);
    } catch (e) {
      // Fallback: try legacy demo email against API if new one fails.
      try {
        await widget.state.demoLogin(
          'admin@customshield.local',
          _password.text,
        );
      } catch (_) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.state.backToChooser,
        ),
        title: const Text('Pulsar · Админ'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 12),
              const Text(
                'Вход в конструктор',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: PulsarColors.text,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Управляйте своим VPS и ключами клиентов. '
                'Это не продажа VPN — только ваш сервер.',
                style: TextStyle(color: PulsarColors.textMuted, height: 1.4),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Пароль'),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: PulsarColors.danger)),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: PulsarColors.text,
                  foregroundColor: PulsarColors.bg,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Войти'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Локальный демо: admin@pulsar.local / demo-admin\n'
                '(нужен API с CS_LOCAL_DEMO=1)',
                style: TextStyle(fontSize: 12, color: PulsarColors.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
