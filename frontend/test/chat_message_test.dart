import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mustafeed/screens/chat_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ChatMessage renders and copies text', (WidgetTester tester) async {
    const messageText = 'Test Message';
    
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatMessage(
          id: '1',
          text: messageText,
          isUser: false,
        ),
      ),
    ));

    expect(find.text(messageText), findsOneWidget);
    
    // Check for icons by type to avoid IconData issues in tests
    expect(find.byType(Icon), findsNWidgets(2));
    
    // Tap the copy icon (second one)
    await tester.tap(find.byType(Icon).last);
    await tester.pump();
    
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboardData?.text, equals(messageText));
  });
}
