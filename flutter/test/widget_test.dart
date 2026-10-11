import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customshield/main.dart';

void main() {
  testWidgets('Role gate shows Pulsar VPN brand', (tester) async {
    await tester.pumpWidget(const PulsarApp());
    expect(find.text('Pulsar VPN'), findsWidgets);
    expect(find.textContaining('Я админ'), findsOneWidget);
    expect(find.textContaining('У меня есть ключ'), findsOneWidget);
  });

  testWidgets('Client mode shows connect UI', (tester) async {
    await tester.pumpWidget(const PulsarApp());
    await tester.tap(find.textContaining('У меня есть ключ'));
    await tester.pumpAndSettle();
    expect(find.text('Отключено'), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new_rounded), findsOneWidget);
  });
}
