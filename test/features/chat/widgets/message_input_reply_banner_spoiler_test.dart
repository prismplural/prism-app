import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/chat_message.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/widgets/message_input.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'ReplyBanner redacts ||spoilers|| in the composer preview',
    (tester) async {
      final alice = Member(
        id: 'alice-id',
        name: 'Alice',
        createdAt: DateTime(2026, 1, 1),
        isActive: true,
      );

      final message = ChatMessage(
        id: 'msg-1',
        conversationId: 'conv-1',
        content: 'hello ||surprise|| world',
        timestamp: DateTime(2026, 4, 20, 12),
        authorId: 'alice-id',
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReplyBanner(
              message: message,
              memberMap: {'alice-id': alice},
              onDismiss: () {},
            ),
          ),
        ),
      );

      // Collect the text of every Text widget inside the banner.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' | ');

      expect(texts, isNot(contains('surprise')));
      expect(texts, contains('\u25AE'));
      // Surrounding plaintext still shows.
      expect(texts, contains('hello '));
      expect(texts, contains(' world'));
    },
  );
}
