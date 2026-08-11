import 'package:flutter_test/flutter_test.dart';

import 'package:aevora_web/config.dart';
import 'package:aevora_web/main.dart';

void main() {
  testWidgets('App shows key setup when no keys stored', (WidgetTester tester) async {
    await tester.pumpWidget(const AevoraWebApp(keys: KeySettings()));
    await tester.pumpAndSettle();
    expect(find.text(appName), findsOneWidget);
  });

  test('userId derivation is stable and isolated', () {
    const a = KeySettings(geminiKey: 'k1', groqKey: 'g1');
    const b = KeySettings(geminiKey: 'k1', groqKey: 'g2');
    expect(AppStorage.deriveUserId(a), isNot(AppStorage.deriveUserId(b)));
    expect(AppStorage.deriveUserId(a), AppStorage.deriveUserId(a));
  });
}
