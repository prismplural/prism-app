import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/custom_field_detail_screen.dart';
import 'package:prism_plurality/features/settings/views/custom_fields_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _testApp(
  db.AppDatabase database,
  Widget child, {
  Locale locale = const Locale('en'),
  bool withToastHost = false,
}) {
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
      locale: locale,
      home: withToastHost ? PrismToastHost(child: child) : child,
    ),
  );
}

Widget _testAppWithCustomFieldNotifier(
  db.AppDatabase database,
  Widget child,
  CustomFieldNotifier notifier,
) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(database),
      terminologySettingProvider.overrideWithValue((
        term: SystemTerminology.headmates,
        customSingular: null,
        customPlural: null,
        useEnglish: false,
      )),
      customFieldNotifierProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PrismToastHost(child: child),
    ),
  );
}

class _FailingReorderCustomFieldNotifier extends CustomFieldNotifier {
  int reorderCalls = 0;

  @override
  Future<void> build() async {}

  @override
  Future<void> reorderFields(List<CustomField> fields) async {
    reorderCalls++;
    throw Exception('forced reorder failure');
  }
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

  testWidgets('filled-in members list builds rows lazily', (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    for (var i = 0; i < 120; i++) {
      await database.membersDao.insertMember(
        db.MembersCompanion.insert(
          id: 'm-$i',
          name: 'Member $i',
          createdAt: DateTime(2026, 1, 1),
          displayOrder: Value(i),
        ),
      );
      await database.customFieldsDao.upsertValue(
        db.CustomFieldValuesCompanion.insert(
          id: 'v-$i',
          customFieldId: 'role',
          memberId: 'm-$i',
          value: 'Value $i',
        ),
      );
    }

    await tester.pumpWidget(
      _testApp(database, const CustomFieldDetailScreen(fieldId: 'role')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Filled in for 120 headmates'), findsOneWidget);
    expect(find.text('Member 0'), findsOneWidget);
    expect(
      find.text('Member 119'),
      findsNothing,
      reason:
          'large filled-in lists should not build every offscreen row on first paint',
    );

    await tester.scrollUntilVisible(
      find.text('Member 119'),
      720,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Member 119'), findsOneWidget);

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

  testWidgets('suggests long text when multiple short text values are long', (
    tester,
  ) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    for (final member in [('m-1', 'Alice'), ('m-2', 'Bea'), ('m-3', 'Cam')]) {
      await database.membersDao.insertMember(
        db.MembersCompanion.insert(
          id: member.$1,
          name: member.$2,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
    }
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'role-notes',
        name: 'Role notes',
        fieldType: 0,
        createdAt: DateTime(2026, 1, 3),
      ),
    );
    for (final value in [
      (
        'v-1',
        'm-1',
        'Usually prefers careful check-ins after stressful days. '
            'They appreciate context, a little quiet, and enough room to explain.',
      ),
      (
        'v-2',
        'm-2',
        'Keeps a detailed list of grounding preferences, support '
            'signals, and things that should be handled gently.',
      ),
      ('v-3', 'm-3', 'Short'),
    ]) {
      await database.customFieldsDao.upsertValue(
        db.CustomFieldValuesCompanion.insert(
          id: value.$1,
          customFieldId: 'role-notes',
          memberId: value.$2,
          value: value.$3,
        ),
      );
    }

    await tester.pumpWidget(
      _testApp(database, const CustomFieldDetailScreen(fieldId: 'role-notes')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This field is collecting longer answers. Long Text may be easier to read and edit.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('localizes custom field type labels in Spanish', (tester) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    for (final member in [('m-1', 'Alicia'), ('m-2', 'Bea')]) {
      await database.membersDao.insertMember(
        db.MembersCompanion.insert(
          id: member.$1,
          name: member.$2,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
    }
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'role-notes',
        name: 'Notas de rol',
        fieldType: 0,
        createdAt: DateTime(2026, 1, 3),
      ),
    );
    for (final value in [
      (
        'v-1',
        'm-1',
        'Prefiere check-ins tranquilos después de días largos, con contexto suficiente para explicar lo que necesita.',
      ),
      (
        'v-2',
        'm-2',
        'Mantiene una lista detallada de preferencias de apoyo, señales y temas que conviene manejar con cuidado.',
      ),
    ]) {
      await database.customFieldsDao.upsertValue(
        db.CustomFieldValuesCompanion.insert(
          id: value.$1,
          customFieldId: 'role-notes',
          memberId: value.$2,
          value: value.$3,
        ),
      );
    }

    await tester.pumpWidget(
      _testApp(
        database,
        const CustomFieldDetailScreen(fieldId: 'role-notes'),
        locale: const Locale('es'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Texto corto'), findsOneWidget);
    expect(
      find.textContaining('Texto largo puede ser más fácil'),
      findsOneWidget,
    );
    expect(find.textContaining('Long Text'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('does not suggest long text for a single long short text value', (
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
        id: 'role-notes',
        name: 'Role notes',
        fieldType: 0,
        createdAt: DateTime(2026, 1, 3),
      ),
    );
    await database.customFieldsDao.upsertValue(
      db.CustomFieldValuesCompanion.insert(
        id: 'v-1',
        customFieldId: 'role-notes',
        memberId: 'm-1',
        value:
            'Usually prefers careful check-ins after stressful days. They appreciate context, quiet, and enough room to explain.',
      ),
    );

    await tester.pumpWidget(
      _testApp(database, const CustomFieldDetailScreen(fieldId: 'role-notes')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Long Text may be easier'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('does not suggest long text for long text fields', (
    tester,
  ) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    for (final member in [('m-1', 'Alice'), ('m-2', 'Bea')]) {
      await database.membersDao.insertMember(
        db.MembersCompanion.insert(
          id: member.$1,
          name: member.$2,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
    }
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'backstory',
        name: 'Backstory',
        fieldType: 3,
        createdAt: DateTime(2026, 1, 3),
      ),
    );
    for (final value in [('v-1', 'm-1'), ('v-2', 'm-2')]) {
      await database.customFieldsDao.upsertValue(
        db.CustomFieldValuesCompanion.insert(
          id: value.$1,
          customFieldId: 'backstory',
          memberId: value.$2,
          value:
              'A very long value that already belongs to a long text field, so no conversion nudge should appear.',
        ),
      );
    }

    await tester.pumpWidget(
      _testApp(database, const CustomFieldDetailScreen(fieldId: 'backstory')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Long Text may be easier'), findsNothing);

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

  testWidgets('settings row long-press menu opens upward near bottom edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    for (final (:id, :name, :order) in [
      (id: 'sleepy', name: 'Sleepy?', order: 0),
      (id: 'options', name: 'Options?', order: 1),
      (id: 'focus', name: 'Focus?', order: 2),
    ]) {
      await database.customFieldsDao.createField(
        db.CustomFieldsCompanion.insert(
          id: id,
          name: name,
          fieldType: 0,
          displayOrder: Value(order),
          createdAt: DateTime(2026, 1, order + 1),
        ),
      );
    }

    await tester.pumpWidget(_testRouterApp(database));
    await tester.pumpAndSettle();

    final row = find.text('Focus?');
    expect(row, findsOneWidget);

    await tester.longPress(row);
    await tester.pumpAndSettle();

    final edit = find.text('Edit');
    expect(edit, findsOneWidget);
    expect(
      tester.getTopLeft(edit).dy,
      lessThan(tester.getTopLeft(row).dy),
      reason: 'bottom-edge row menus should open upward instead of clipping',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('group child reorder failure reverts optimistic order', (
    tester,
  ) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    final notifier = _FailingReorderCustomFieldNotifier();
    addTearDown(database.close);
    addTearDown(PrismToast.resetForTest);

    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'profile-section',
        name: 'Profile section',
        fieldType: 5,
        fieldTypeId: const Value('group'),
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'birthday',
        name: 'Birthday',
        fieldType: 4,
        parentFieldId: const Value('profile-section'),
        displayOrder: const Value(0),
        createdAt: DateTime(2026, 1, 2),
      ),
    );
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'favorite-color',
        name: 'Favorite color',
        fieldType: 0,
        parentFieldId: const Value('profile-section'),
        displayOrder: const Value(1),
        createdAt: DateTime(2026, 1, 3),
      ),
    );

    await tester.pumpWidget(
      _testAppWithCustomFieldNotifier(
        database,
        const CustomFieldDetailScreen(fieldId: 'profile-section'),
        notifier,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Birthday')).dy,
      lessThan(tester.getTopLeft(find.text('Favorite color')).dy),
    );

    final handles = find.byType(ReorderableDragStartListener);
    expect(handles, findsNWidgets(2));
    final gesture = await tester.startGesture(tester.getCenter(handles.at(1)));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, -180));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(notifier.reorderCalls, 1);
    expect(
      tester.getTopLeft(find.text('Birthday')).dy,
      lessThan(tester.getTopLeft(find.text('Favorite color')).dy),
      reason: 'failed reorder should clear the optimistic child order',
    );
    expect(find.textContaining('forced reorder failure'), findsOneWidget);

    PrismToast.resetForTest();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('settings list renders grouped fields from indexed data', (
    tester,
  ) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'profile-section',
        name: 'Profile section',
        fieldType: 5,
        fieldTypeId: const Value('group'),
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'favorite-color',
        name: 'Favorite color',
        fieldType: 0,
        parentFieldId: const Value('profile-section'),
        displayOrder: const Value(1),
        createdAt: DateTime(2026, 1, 2),
      ),
    );
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'birthday',
        name: 'Birthday',
        fieldType: 4,
        parentFieldId: const Value('profile-section'),
        displayOrder: const Value(0),
        createdAt: DateTime(2026, 1, 3),
      ),
    );

    await tester.pumpWidget(_testRouterApp(database));
    await tester.pumpAndSettle();

    expect(find.text('Profile section'), findsOneWidget);
    expect(find.text('Birthday'), findsOneWidget);
    expect(find.text('Favorite color'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Birthday')).dy,
      lessThan(tester.getTopLeft(find.text('Favorite color')).dy),
    );

    await tester.tap(find.text('Birthday'));
    await tester.pumpAndSettle();

    expect(find.text('Filled In'), findsOneWidget);
    expect(find.text('Nothing filled in yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
