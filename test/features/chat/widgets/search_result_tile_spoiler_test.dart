import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/models/search_result.dart';
import 'package:prism_plurality/features/chat/widgets/search_result_tile.dart';

void main() {
  String renderedText(WidgetTester tester) {
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
    return buffer.toString();
  }

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

      final rendered = renderedText(tester);

      expect(rendered, contains('\u25AE'));
      expect(rendered, isNot(contains('secret')));
    },
  );

  testWidgets(
    'SearchResultTile renders @[uuid] mentions as @MemberName',
    (tester) async {
      const aliceId = '11111111-2222-3333-4444-555555555555';
      final result = MessageSearchResult(
        messageId: 'msg-mention',
        conversationId: 'conv-1',
        snippet: 'hey @[$aliceId] check this',
        timestamp: DateTime(2026, 4, 20, 12),
        authorName: 'Bob',
        conversationTitle: 'General',
      );

      final alice = Member(
        id: aliceId,
        name: 'Alice',
        createdAt: DateTime(2026, 1, 1),
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
                    authorMap: {aliceId: alice},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final rendered = renderedText(tester);
      expect(rendered, contains('@Alice'));
      expect(rendered, isNot(contains(aliceId)));
      expect(rendered, isNot(contains('@[')));
    },
  );

  testWidgets(
    'SearchResultTile renders unknown mention IDs as @Unknown, not raw UUID',
    (tester) async {
      const ghostId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      final result = MessageSearchResult(
        messageId: 'msg-mention-missing',
        conversationId: 'conv-1',
        snippet: 'ping @[$ghostId] please',
        timestamp: DateTime(2026, 4, 20, 12),
        authorName: 'Bob',
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

      final rendered = renderedText(tester);
      expect(rendered, contains('@Unknown'));
      expect(rendered, isNot(contains(ghostId)));
    },
  );

  testWidgets(
    'SearchResultTile Semantics label redacts spoilers for screen readers',
    (tester) async {
      final handle = tester.ensureSemantics();

      final result = MessageSearchResult(
        messageId: 'msg-2',
        conversationId: 'conv-1',
        snippet: 'hello ||secret|| [match]',
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

      final semantics = tester.getSemantics(find.byType(SearchResultTile));
      expect(semantics.label, isNot(contains('secret')));
      // Screen readers get the word "spoiler" instead of raw ▮ blocks so
      // the announcement is meaningful, not a string of block glyphs.
      expect(semantics.label, contains('spoiler'));
      expect(semantics.label, isNot(contains('\u25AE')));
      handle.dispose();
    },
  );
}
