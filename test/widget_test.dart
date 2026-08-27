// Smoke test dasar: pastikan aplikasi WTN Blasting bisa dibangun tanpa error.
// (File bawaan template Flutter sebelumnya masih memakai class MyApp/counter
// demo yang tidak pernah ada di aplikasi ini — sudah tidak sesuai sejak lama,
// diperbaiki di sini supaya `flutter analyze`/`flutter test` tidak error.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wtn_blasting_app/main.dart';

void main() {
  testWidgets('App bisa dibangun tanpa error', (WidgetTester tester) async {
    await tester.pumpWidget(const WtnBlastingApp());
    await tester.pump();
    expect(find.byType(WtnBlastingApp), findsOneWidget);
  });
}

