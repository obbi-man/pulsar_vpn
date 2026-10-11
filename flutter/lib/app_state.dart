import 'package:flutter/foundation.dart';

import 'api/pulsar_api.dart';

enum AppMode { choose, client, admin }

/// Lightweight app-wide state (no external state package).
class PulsarAppState extends ChangeNotifier {
  PulsarAppState({PulsarApi? api}) : api = api ?? PulsarApi();

  final PulsarApi api;

  AppMode mode = AppMode.choose;
  bool adminLoggedIn = false;
  String? adminEmail;

  void chooseClient() {
    mode = AppMode.client;
    notifyListeners();
  }

  void chooseAdmin() {
    mode = AppMode.admin;
    notifyListeners();
  }

  void backToChooser() {
    mode = AppMode.choose;
    notifyListeners();
  }

  Future<void> demoLogin(String email, String password) async {
    final res = await api.demoLogin(email: email, password: password);
    adminLoggedIn = true;
    adminEmail = res['email']?.toString() ?? email;
    notifyListeners();
  }

  Future<void> logoutAdmin() async {
    await api.logout();
    adminLoggedIn = false;
    adminEmail = null;
    notifyListeners();
  }
}
