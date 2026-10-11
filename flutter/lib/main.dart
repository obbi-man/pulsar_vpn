import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'screens/admin/login_screen.dart';
import 'screens/admin/shell_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/role_gate_screen.dart';
import 'theme/pulsar_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: PulsarColors.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const PulsarApp());
}

class PulsarApp extends StatefulWidget {
  const PulsarApp({super.key});

  @override
  State<PulsarApp> createState() => _PulsarAppState();
}

class _PulsarAppState extends State<PulsarApp> {
  final PulsarAppState _state = PulsarAppState();

  @override
  void initState() {
    super.initState();
    _state.addListener(_onState);
  }

  @override
  void dispose() {
    _state.removeListener(_onState);
    _state.dispose();
    super.dispose();
  }

  void _onState() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pulsar VPN',
      debugShowCheckedModeBanner: false,
      theme: buildPulsarTheme(),
      home: _home(),
    );
  }

  Widget _home() {
    switch (_state.mode) {
      case AppMode.choose:
        return RoleGateScreen(state: _state);
      case AppMode.client:
        return ConnectScreen(
          onBack: _state.backToChooser,
        );
      case AppMode.admin:
        if (!_state.adminLoggedIn) {
          return AdminLoginScreen(state: _state);
        }
        return AdminShellScreen(state: _state);
    }
  }
}

/// Back-compat alias for older tests.
typedef CustomShieldApp = PulsarApp;
