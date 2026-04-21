import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/models/search_result.dart';
import 'package:prism_plurality/features/chat/widgets/search_result_tile.dart';

void main() {
  testWidgets(
    'SearchResultTile redacts ||spoiler|| spans in the snippet',
    (tester) async {
      final result = MessageSearchResult(
        messageId: 'msg-1',
        conversationId: 'conv-1',
        snippet: 'hello ||secret||',
        timestamp: DateTime(2026, 4, 20, 12),
        authorName: 'Alice',
        conversationTitle: 'General',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: SearchResultTile(
                    result: result,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Gather all rendered text from RichText spans.
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      final buffer = StringBuffer();
      for (final rt in richTexts) {
        rt.text.visitChildren((span) {
          if (span is TextSpan && span.text != null) {
            buffer.write(span.text);
          }
          return true;
        });
      }
      final rendered = buffer.toString();

      expect(rendered, contains('\u25AE'));
      expect(rendered, isNot(contains('secret')));
    },
  );
}
