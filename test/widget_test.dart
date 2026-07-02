import 'package:flutter_test/flutter_test.dart';
import 'package:chatapp_flutter/main.dart';

void main() {
  testWidgets('App starts successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const ChatApp());
    expect(find.text('ChatApp'), findsWidgets);
  });
}
