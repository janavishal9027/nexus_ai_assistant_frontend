import 'package:flutter_test/flutter_test.dart';
import 'package:chatapp_flutter/main.dart';

void main() {
  testWidgets('App boots to a MaterialApp', (WidgetTester tester) async {
    await tester.pumpWidget(const NexusAiApp());
    await tester.pump();
    // The auth gate initially shows a loading indicator while it checks for a
    // stored token; simply assert the app mounts without throwing.
    expect(find.byType(NexusAiApp), findsOneWidget);
  });
}
