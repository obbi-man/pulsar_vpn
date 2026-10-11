import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/pulsar_api.dart';
import '../../models/access_key.dart';
import '../../theme/pulsar_theme.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, required this.api});

  final PulsarApi api;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  int _used = 0;
  int? _limit = 20;
  String _plan = 'free';
  Map<String, dynamic>? _server;

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
      final data = await widget.api.listUsers();
      final list = (data['users'] as List?) ?? [];
      setState(() {
        _users = list.cast<Map<String, dynamic>>();
        _used = (data['used'] as num?)?.toInt() ?? _users.length;
        _limit = data['limit'] as int?;
        _plan = data['plan']?.toString() ?? 'free';
        _server = data['server'] as Map<String, dynamic>?;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _atLimit => _limit != null && _used >= _limit!;

  Future<void> _create() async {
    if (_atLimit) {
      _showLimitDialog();
      return;
    }
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PulsarColors.surface,
        title: const Text('Новый пользователь'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Имя'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    try {
      final res = await widget.api.createUser(nameCtrl.text.trim());
      final url = res['access_url']?.toString();
      await _load();
      if (!mounted) return;
      if (url != null) {
        // Prefer pulsar:// display.
        String display = url;
        try {
          display = AccessKey.parse(url).displayUrl;
        } catch (_) {}
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: PulsarColors.surface,
            title: const Text('Ключ доступа'),
            content: SelectableText(
              display,
              style: const TextStyle(fontSize: 13, color: PulsarColors.accent),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: display));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Копировать'),
              ),
            ],
          ),
        );
      }
    } on PulsarApiException catch (e) {
      if (e.limitReached) {
        _showLimitDialog();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _showLimitDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PulsarColors.surface,
        title: const Text('Лимит Free'),
        content: Text(
          'Достигнут лимит Free (${_limit ?? 20} пользователей). '
          'Перейдите на Pro, чтобы добавить больше.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Пользователи',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: PulsarColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_plan · $_used${_limit != null ? ' / $_limit' : ' / ∞'}'
                      '${_server != null ? ' · ${_server!['ip_address']}' : ''}',
                      style: const TextStyle(
                        color: PulsarColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _create,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Создать'),
                style: FilledButton.styleFrom(
                  backgroundColor: PulsarColors.text,
                  foregroundColor: PulsarColors.bg,
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(_error!, style: const TextStyle(color: PulsarColors.danger)),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _users.isEmpty
                  ? const Center(
                      child: Text(
                        'Пока нет пользователей',
                        style: TextStyle(color: PulsarColors.textDim),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final u = _users[i];
                        final raw = u['access_url']?.toString() ?? '';
                        String display = raw;
                        try {
                          if (raw.isNotEmpty) {
                            display = AccessKey.parse(raw).displayUrl;
                          }
                        } catch (_) {}
                        return Material(
                          color: PulsarColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        u['name']?.toString() ?? '—',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      u['connection_id']?.toString() ?? '',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: PulsarColors.textDim,
                                      ),
                                    ),
                                  ],
                                ),
                                if (display.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  GestureDetector(
                                    onTap: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: display),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text('Ключ скопирован'),
                                          ),
                                        );
                                      }
                                    },
                                    child: Text(
                                      display,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: PulsarColors.accent,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
