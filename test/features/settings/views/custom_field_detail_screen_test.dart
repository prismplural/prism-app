import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/custom_field_detail_screen.dart';
import 'package:prism_plurality/features/settings/views/custom_fields_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _testApp(db.AppDatabase database, Widget child) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(database),
      terminologySettingProvider.overrideWithValue((
        term: SystemTerminology.headmates,
        customSingular: null,
        customPlural: null,
        useEnglish: false,
      )),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

Widget _testRouterApp(db.AppDatabase database) {
  final router = GoRouter(
    initialLocation: AppRoutePaths.settingsCustomFields,
    routes: [
      GoRoute(
        path: AppRoutePaths.settingsCustomFields,
        builder: (context, state) => const CustomFieldsScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) =>
                CustomFieldDetailScreen(fieldId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(database),
      terminologySettingProvider.overrideWithValue((
        term: SystemTerminology.headmates,
        customSingular: null,
        customPlural: null,
        useEnglish: false,
      )),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('shows members with values and previews long text', (
    tester,
  ) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await database.membersDao.insertMember(
      db.MembersCompanion.insert(
        id: 'm-1',
        name: 'Alice',
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await database.membersDao.insertMember(
      db.MembersCompanion.insert(
        id: 'm-2',
        name: 'Bea',
        createdAt: DateTime(2026, 1, 2),
      ),
    );
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'backstory',
        name: 'Backstory',
        fieldType: 3,
        createdAt: DateTime(2026, 1, 3),
      ),
    );
    await database.customFieldsDao.upsertValue(
      db.CustomFieldValuesCompanion.insert(
        id: 'v-1',
        customFieldId: 'backstory',
        memberId: 'm-1',
        value:
            'A very long value that should be previewed on the settings detail screen. '
            'It keeps going with enough content to exceed the preview character limit. '
            'The important beginning should remain visible for quick scanning. '
            'This middle portion adds more words and line length for the preview clamp. '
            'HiddenTailShouldNotRender',
      ),
    );
    await database.customFieldsDao.upsertValue(
      db.CustomFieldValuesCompanion.insert(
        id: 'v-2',
        customFieldId: 'backstory',
        memberId: 'm-2',
        value: 'Short value',
      ),
    );

    await tester.pumpWidget(
      _testApp(database, const CustomFieldDetailScreen(fieldId: 'backstory')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backstory'), findsOneWidget);
    expect(find.text('Long Text'), findsOneWidget);
    expect(find.text('Filled In'), findsOneWidget);
    expect(find.text('Filled in for 2 headmates'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bea'), findsOneWidget);
    expect(find.textContaining('A very long value'), findsOneWidget);
    expect(find.text('Short value'), findsOneWidget);
    expect(find.textContaining('HiddenTailShouldNotRender'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('uses singular terminology for one filled-in member', (
    tester,
  ) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await database.membersDao.insertMember(
      db.MembersCompanion.insert(
        id: 'm-1',
        name: 'Alice',
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'role',
        name: 'Role',
        fieldType: 0,
        createdAt: DateTime(2026, 1, 3),
      ),
    );
    await database.customFieldsDao.upsertValue(
      db.CustomFieldValuesCompanion.insert(
        id: 'v-1',
        customFieldId: 'role',
        memberId: 'm-1',
        value: 'Protector',
      ),
    );

    await tester.pumpWidget(
      _testApp(database, const CustomFieldDetailScreen(fieldId: 'role')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Filled in for 1 headmate'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('shows an empty filled-in state when no members have values', (
    tester,
  ) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'role',
        name: 'Role',
        fieldType: 0,
        createdAt: DateTime(2026, 1, 3),
      ),
    );

    await tester.pumpWidget(
      _testApp(database, const CustomFieldDetailScreen(fieldId: 'role')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Filled in for 0 headmates'), findsOneWidget);
    expect(find.text('Nothing filled in yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('edit action opens the existing edit field sheet', (
    tester,
  ) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'role',
        name: 'Role',
        fieldType: 0,
        createdAt: DateTime(2026, 1, 3),
      ),
    );

    await tester.pumpWidget(
      _testApp(database, const CustomFieldDetailScreen(fieldId: 'role')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Field'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('delete action opens the destructive confirmation dialog', (
    tester,
  ) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'role',
        name: 'Role',
        fieldType: 0,
        createdAt: DateTime(2026, 1, 3),
      ),
    );

    await tester.pumpWidget(_testRouterApp(database));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Role'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Field'), findsOneWidget);
    expect(
      find.text(
        'Are you sure you want to delete "Role"? This will delete the field and all its values.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('list rows navigate to the custom field detail route', (
    tester,
  ) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'role',
        name: 'Role',
        fieldType: 0,
        createdAt: DateTime(2026, 1, 3),
      ),
    );

    await tester.pumpWidget(_testRouterApp(database));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Role'));
    await tester.pumpAndSettle();

    expect(find.text('Filled In'), findsOneWidget);
    expect(find.text('Nothing filled in yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
