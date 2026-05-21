import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/members/providers/profile_entity_mentions_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/mentions/entity_mention.dart';
import 'package:prism_plurality/shared/widgets/entity_mention_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/entity_mention_text.dart';

void main() {
  testWidgets('markdown-disabled profile text still resolves entity mentions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const EntityMentionMarkdownText(
          data: 'hello @[note:secret] and @[member:m1]',
          enabled: false,
        ),
        resolutions: {
          const EntityMentionTarget(
            type: EntityMentionType.note,
            id: 'secret',
          ): const ProfileEntityMentionResolution(
            target: EntityMentionTarget(
              type: EntityMentionType.note,
              id: 'secret',
            ),
            visible: false,
          ),
          const EntityMentionTarget(
            type: EntityMentionType.member,
            id: 'm1',
          ): const ProfileEntityMentionResolution(
            target: EntityMentionTarget(
              type: EntityMentionType.member,
              id: 'm1',
            ),
            visible: true,
            label: 'Alice',
          ),
        },
      ),
    );

    expect(_firstRichTextPlainText(tester), 'hello Private and @Alice');
  });

  testWidgets('visible labels render as plain text, not markdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const EntityMentionInlineText(data: 'hi @[member:m1]'),
        resolutions: {
          const EntityMentionTarget(
            type: EntityMentionType.member,
            id: 'm1',
          ): const ProfileEntityMentionResolution(
            target: EntityMentionTarget(
              type: EntityMentionType.member,
              id: 'm1',
            ),
            visible: true,
            label: '**Alice**',
          ),
        },
      ),
    );

    expect(_firstRichTextPlainText(tester), 'hi @**Alice**');
  });

  testWidgets('editing controller keeps span plain text equal to raw text', (
    tester,
  ) async {
    final controller = EntityMentionEditingController(
      text: 'hi @[member:m1] **bold**',
    );
    late String plainText;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            controller.updateTheme(context);
            controller.updateMentionResolutions(
              resolutions: {
                const EntityMentionTarget(
                  type: EntityMentionType.member,
                  id: 'm1',
                ): const ProfileEntityMentionResolution(
                  target: EntityMentionTarget(
                    type: EntityMentionType.member,
                    id: 'm1',
                  ),
                  visible: true,
                  label: 'Alice',
                ),
              },
              hiddenLabel: 'Private',
            );
            plainText = controller
                .buildTextSpan(
                  context: context,
                  style: const TextStyle(),
                  withComposing: false,
                )
                .toPlainText();
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(plainText, controller.text);
  });
}

Widget _wrap(
  Widget child, {
  required Map<EntityMentionTarget, ProfileEntityMentionResolution> resolutions,
}) {
  return ProviderScope(
    overrides: [
      profileEntityMentionResolutionsProvider.overrideWith(
        (ref, text) => resolutions,
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

String _firstRichTextPlainText(WidgetTester tester) {
  final richText = tester.widget<RichText>(find.byType(RichText).first);
  return richText.text.toPlainText();
}
