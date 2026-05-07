import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

Finder _prismField(String label) => find.byWidgetPredicate(
  (widget) => widget is PrismTextField && widget.labelText == label,
);

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('save button persists a focused custom field value', (
    tester,
  ) async {
    _useTallViewport(tester);

    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final member = Member(
      id: 'm-1',
      name: 'Alice',
      createdAt: DateTime(2026, 1, 1),
    );
    await database.membersDao.insertMember(
      db.MembersCompanion.insert(
        id: member.id,
        name: member.name,
        createdAt: member.createdAt,
      ),
    );
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'role',
        name: 'Role',
        fieldType: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          terminologySettingProvider.overrideWithValue((
            term: SystemTerminology.members,
            customSingular: null,
            customPlural: null,
            useEnglish: false,
          )),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AddEditMemberSheet(
              member: member,
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      _prismField('Role'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.descendant(
        of: _prismField('Role'),
        matching: find.byType(EditableText),
      ),
      'Protector',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Save member'));
    await tester.pumpAndSettle();

    final values = await database.customFieldsDao.getAllValues();
    expect(values, hasLength(1));
    expect(values.single.customFieldId, 'role');
    expect(values.single.memberId, 'm-1');
    expect(values.single.value, 'Protector');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
