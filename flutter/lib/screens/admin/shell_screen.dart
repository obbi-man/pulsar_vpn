import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../theme/pulsar_theme.dart';
import 'pricing_screen.dart';
import 'server_screen.dart';
import 'users_screen.dart';

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key, required this.state});

  final PulsarAppState state;

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      AdminServerScreen(api: widget.state.api),
      AdminUsersScreen(api: widget.state.api),
      AdminPricingScreen(api: widget.state.api),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pulsar VPN'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                widget.state.adminEmail ?? 'admin',
                style: const TextStyle(
                  fontSize: 12,
                  color: PulsarColors.textMuted,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Выйти',
            onPressed: () async {
              await widget.state.logoutAdmin();
            },
            icon: const Icon(Icons.logout_rounded),
          ),
          IconButton(
            tooltip: 'Режим',
            onPressed: widget.state.backToChooser,
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: PulsarColors.surface,
        indicatorColor: PulsarColors.surfaceElevated,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns_rounded),
            label: 'Сервер',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Клиенты',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium_rounded),
            label: 'Тариф',
          ),
        ],
      ),
    );
  }
}
