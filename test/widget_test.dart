// Basic smoke test for the Silver Horizon app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:horizongame/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const SilverHorizonApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
