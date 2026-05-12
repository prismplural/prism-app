import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/views/sync_debug_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

/// Notifier override that holds an empty Prism sync event log. We can't drive
/// the real notifier from a test because it watches the Rust FFI sync event
/// stream; subbing a notifier that simply returns `[]` from `build` is the
/// cleanest way to render the Sync Debug Screen in a known state.
class _EmptySyncEventLogNotifier extends SyncEventLogNotifier {
  @override
  List<SyncEventLogEntry> build() => const [];
}

Widget _buildSubject({required GoRouter router}) {
  return ProviderScope(
    overrides: [
      // Force an empty sync event log so the screen renders its empty state
      // (cleanest test surface — no Prism events to fight with the cross-link).
      syncEventLogProvider.overrideWith(_EmptySyncEventLogNotifier.new),
      // Empty fronting migration breadcrumbs so the screen doesn't try to
      // touch the real breadcrumb log on disk.
      frontingMigrationBreadcrumbsProvider.overrideWith(
        (ref) => Future.value(const []),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      routerConfig: router,
    ),
  );
}

void main() {
  group('SyncDebugScreen PK cross-link', () {
    testWidgets('renders a "View PluralKit sync log" cross-link', (tester) async {
      final router = GoRouter(
        initialLocation: '/settings/debug',
        routes: [
          GoRoute(
            path: '/settings/debug',
            builder: (_, _) => const SyncDebugScreen(),
          ),
          GoRoute(
            path: AppRoutePaths.settingsPluralkitSyncDebug,
            builder: (_, _) => const Scaffold(body: Text('pk-sync-debug-route')),
          ),
        ],
      );

      await tester.pumpWidget(_buildSubject(router: router));
      await tester.pumpAndSettle();

      expect(find.text('View PluralKit sync log'), findsOneWidget);
    });

    testWidgets('tapping the cross-link navigates to the PK sync debug route',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/settings/debug',
        routes: [
          GoRoute(
            path: '/settings/debug',
            builder: (_, _) => const SyncDebugScreen(),
          ),
          GoRoute(
            path: AppRoutePaths.settingsPluralkitSyncDebug,
            builder: (_, _) => const Scaffold(body: Text('pk-sync-debug-route')),
          ),
        ],
      );

      await tester.pumpWidget(_buildSubject(router: router));
      await tester.pumpAndSettle();

      // Tap the cross-link.
      await tester.tap(find.text('View PluralKit sync log'));
      await tester.pumpAndSettle();

      // Navigation should have landed on the PK sync debug subroute. We
      // assert on the destination's rendered text rather than the router's
      // currentConfiguration.uri — go_router collapses nested routes when
      // generating that URI in widget tests, so the rendered-text check is
      // the stable invariant.
      expect(find.text('pk-sync-debug-route'), findsOneWidget);
      // SKIP: go_router's currentConfiguration.uri does not reflect the
      // pushed location in widget tests when the destination is registered
      // as a flat top-level GoRoute on the test router. The rendered text
      // assertion above is the user-facing invariant.
    });
  });
}
