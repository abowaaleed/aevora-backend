import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mustafeed/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Aevora shows the mode selection experience', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const AevoraApp());
    await tester.pump();

    expect(find.text('Choose your mode'), findsOneWidget);
    expect(find.text('Quick'), findsOneWidget);
  });
}
