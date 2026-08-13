import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aevora_web/config.dart';
import 'package:aevora_web/screens/login_screen.dart';
import 'package:aevora_web/widgets/google_g_button.dart';

void main() {
  testWidgets('GoogleGButton renders its label text without exceptions',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GoogleGButton(
            label: 'المتابعة بحساب Google',
            onPressed: null,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('المتابعة بحساب Google'), findsOneWidget);
  });

  testWidgets('LoginScreen renders all key elements',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('المتابعة بحساب Google'), findsOneWidget);
    expect(find.text('تسجيل الدخول بنافذة بديلة'), findsOneWidget);
    expect(find.text('المتابعة بدون حساب (محلي على هذا الجهاز فقط)'), findsOneWidget);
    expect(find.text(appName), findsOneWidget);
  });
}
