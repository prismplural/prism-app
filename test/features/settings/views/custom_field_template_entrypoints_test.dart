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

Widget _testApp(db.AppDatabase database, Widget child) => ProviderScope(
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

Widget _testRouterApp(db.AppDatabase database) {
  final router = GoRouter(
    initialLocation: AppRoutePaths.settingsCustomFields,
    routes: [
      GoRoute(
        path: AppRoutePaths.settingsCustomFields,
        builder: (context, state) => const CustomFieldsScreen(),
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

Future<void> _seedField(db.AppDatabase database) {
  return database.customFieldsDao.createField(
    db.CustomFieldsCompanion.insert(
      id: 'role',
      name: 'Role',
      fieldType: 0,
      createdAt: DateTime(2026, 1, 3),
    ),
  );
}

void main() {
  testWidgets('detail screen top bar has a Share as template action', (
    tester,
  ) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedField(database);

    await tester.pumpWidget(
      _testApp(database, const CustomFieldDetailScreen(fieldId: 'role')),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Share as template'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('custom fields screen top bar has an Import template action', (
    tester,
  ) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedField(database);

    await tester.pumpWidget(_testRouterApp(database));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Import template'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('field row long-press menu has Share as template', (tester) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedField(database);

    await tester.pumpWidget(_testRouterApp(database));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Role'));
    await tester.pumpAndSettle();

    expect(find.text('Share as template'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('tapping Share as template opens the share sheet', (tester) async {
    _useTallViewport(tester);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedField(database);

    await tester.pumpWidget(
      _testApp(database, const CustomFieldDetailScreen(fieldId: 'role')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Share as template'));
    await tester.pumpAndSettle();

    expect(find.text('Share template'), findsOneWidget);
    expect(find.text('Role'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
