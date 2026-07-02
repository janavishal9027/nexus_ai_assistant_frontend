import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatapp_flutter/models/conversation.dart';
import 'package:chatapp_flutter/widgets/message_bubble.dart';

// A real ~16k-char architecture response (code blocks + ASCII diagrams) that
// used to crash flutter_markdown with a custom code-block builder.
const _fixture = 'test/fixtures/arch_response.md';

void main() {
  testWidgets('renders complex assistant markdown (code + diagrams) safely',
      (tester) async {
    final content = File(_fixture).readAsStringSync();
    final msg = Message(role: 'assistant', content: content, model: 'Test');

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(child: MessageBubble(message: msg)),
        ),
      ),
    );

    // No render/assertion crash.
    expect(tester.takeException(), isNull);
    // Code blocks are rendered by our own highlighted widget.
    expect(find.byType(HighlightView), findsWidgets);
  });

  testWidgets('handles unclosed fence and empty content', (tester) async {
    for (final c in ['```python\nprint(1)', '', 'plain **text** only', '``` ']) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessageBubble(
                message: Message(role: 'assistant', content: c, model: 'm'),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'failed for: ${c.substring(0, c.length.clamp(0, 20))}');
    }
  });
}
