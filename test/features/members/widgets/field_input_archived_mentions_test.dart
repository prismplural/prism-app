import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/field_input_widget.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  const aliceId = '11111111-2222-3333-4444-555555555555';
  final alice = Member(
    id: aliceId,
    name: 'Alice',
    displayName: 'Alice Full',
    isActive: false,
    createdAt: DateTime(2026),
  );

  for (final type in [CustomFieldType.text, CustomFieldType.longText]) {
    testWidgets(
      '${type.name} resolves archived labels but keeps picker active-only',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              allMemberListProvider.overrideWithValue(AsyncValue.data([alice])),
              activeMemberListProvider.overrideWithValue(
                const AsyncValue.data([]),
              ),
              memberNamePreferDisplayProvider.overrideWithValue(true),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: FieldInputWidget(
                  field: CustomField(
                    id: 'field',
                    name: 'Synthetic field',
                    fieldType: type,
                    fieldTypeId: type.name,
                    createdAt: DateTime(2026),
                  ),
                  memberId: 'synthetic-owner',
                  existingValue: const CustomFieldValue(
                    id: 'value',
                    customFieldId: 'field',
                    memberId: 'synthetic-owner',
                    value: 'Saved @[$aliceId]',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        final editable = tester.widget<EditableText>(find.byType(EditableText));
        final span = editable.controller.buildTextSpan(
          context: tester.element(find.byType(EditableText)),
          style: editable.style,
          withComposing: false,
        );
        // Markdown mention spans pad hidden token offsets with U+200B.
        expect(
          span.toPlainText().replaceAll('\u200B', ''),
          'Saved @Alice Full',
        );
        if (type == CustomFieldType.longText) {
          expect(span.toPlainText().length, editable.controller.text.length);
        }
        expect(editable.controller.text, 'Saved @[$aliceId]');

        await tester.enterText(find.byType(EditableText), '@Ali');
        await tester.pump();
        expect(
          find.byKey(const Key('memberMentionOverlaySurface')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
