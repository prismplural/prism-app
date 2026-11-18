// Mobile nav bar label placement under text scaling.
//
// The row height comes from the scaled label, so the label's offset below the row
// centre and the icon's lift have to follow that same measured line box. A constant
// tuned for 1x text puts the label over the icon as soon as the text scales - about
// 20dp of overlap at 3.375x.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/database_providers.dart'
    show appPreferenceRepositoryProvider;
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_auto_poll_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';

import '../../helpers/fake_repositories.dart' show FakeAppPreferenceRepository;
import '../../helpers/prism_golden.dart' show loadPrismGoldenFonts;

class _NonLinearTextScaler extends TextScaler {
  const _NonLinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 1.4 : 28.0 + (fontSize - 20) * 3.0;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 3.0;
}

const _scales = <(String, TextScaler)>[
  (
    'system 100% x Prism 50% = 0.5x',
    PrismTextScaler(TextScaler.noScaling, 0.5),
  ),
  ('default text', PrismTextScaler(TextScaler.noScaling, 1.0)),
  ('large text 1.5x', PrismTextScaler(TextScaler.linear(1.5), 1.0)),
  (
    'system 225% x Prism 150% = 3.375x',
    PrismTextScaler(TextScaler.linear(2.25), 1.5),
  ),
  (
    'nonlinear system scaler x Prism 150%',
    PrismTextScaler(_NonLinearTextScaler(), 1.5),
  ),
];

const _tabIds = ['home', 'chat', 'habits', 'polls', 'settings'];

class _FakeSyncStatusNotifier extends SyncStatusNotifier {
  @override
  SyncStatus build() => const SyncStatus();
}

class _UnreadCountNotifier extends Notifier<int> {
  @override
  int build() => 0;

  set value(int newValue) => state = newValue;
}

final _unreadCountStateProvider = NotifierProvider<_UnreadCountNotifier, int>(
  _UnreadCountNotifier.new,
);

class _FakePkAutoPollNotifier extends PkAutoPollNotifier {
  @override
  void build() {}

  @override
  void markForegrounded(bool value) {}

  @override
  void noteLocalPush() {}
}

class _FakePluralKitSyncNotifier extends PluralKitSyncNotifier {
  @override
  PluralKitSyncState build() => const PluralKitSyncState();

  @override
  Future<int> pushPendingSwitches() async => 0;

  @override
  Future<void> pushMemberUpdate(domain.Member member) async {}
}

GoRouter _router() => GoRouter(
  initialLocation: AppRoutePaths.home,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell, routePath: state.uri.path),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutePaths.home,
              builder: (context, state) =>
                  const Scaffold(body: SizedBox.expand()),
            ),
          ],
        ),
      ],
    ),
  ],
);

Widget _subject({
  required GoRouter router,
  required TextScaler textScaler,
  NavBarLabelVisibility labelVisibility = NavBarLabelVisibility.always,
}) {
  return ProviderScope(
    overrides: [
      activeNavBarTabsProvider.overrideWithValue(appShellTabs.take(5).toList()),
      navBarOverflowTabsProvider.overrideWithValue(const <AppShellTab>[]),
      navBarLabelVisibilityProvider.overrideWithValue(labelVisibility),
      appPreferenceRepositoryProvider.overrideWithValue(
        FakeAppPreferenceRepository(),
      ),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      isPinSetProvider.overrideWith((ref) async => false),
      syncStatusProvider.overrideWith(_FakeSyncStatusNotifier.new),
      pkAutoPollProvider.overrideWith(_FakePkAutoPollNotifier.new),
      pluralKitSyncProvider.overrideWith(_FakePluralKitSyncNotifier.new),
      habitsBadgeEnabledProvider.overrideWith((ref) => false),
      activeSessionsProvider.overrideWith((ref) => Stream.value(const [])),
      allMembersProvider.overrideWith((ref) => Stream.value(const [])),
      unreadConversationCountProvider.overrideWith(
        (ref) => ref.watch(_unreadCountStateProvider),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        fontFamily: 'OpenDyslexic',
        fontFamilyFallback: const ['NotoColorEmoji'],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      routerConfig: router,
    ),
  );
}

void _useViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Rect _rowRect(WidgetTester tester, Finder label) {
  return tester.getRect(
    find.ancestor(of: label, matching: find.byType(Stack)).first,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadPrismGoldenFonts();
  });

  for (final (label, scaler) in _scales) {
    testWidgets('label sits below its icon and inside its row ($label)', (
      tester,
    ) async {
      _useViewport(tester, const Size(390, 780));
      final router = _router();
      addTearDown(router.dispose);
      final semantics = tester.ensureSemantics();

      try {
        await tester.pumpWidget(_subject(router: router, textScaler: scaler));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$label: layout error');

        var checked = 0;
        for (final id in _tabIds) {
          final labelFinder = find.byKey(ValueKey('nav_label_$id'));
          final iconFinder = find.byKey(ValueKey('nav_icon_slot_$id'));
          if (labelFinder.evaluate().isEmpty || iconFinder.evaluate().isEmpty) {
            continue; // collapsed into the overflow menu at this width/scale
          }
          checked++;

          final labelRect = tester.getRect(labelFinder);
          final iconRect = tester.getRect(iconFinder);
          final rowRect = _rowRect(tester, labelFinder);

          expect(
            labelRect.top,
            greaterThanOrEqualTo(iconRect.bottom - 1.0),
            reason:
                '$label: the "$id" label starts at '
                '${labelRect.top.toStringAsFixed(1)} but its icon ends at '
                '${iconRect.bottom.toStringAsFixed(1)}',
          );
          expect(
            labelRect.top - iconRect.bottom,
            lessThanOrEqualTo(4.0),
            reason: '$label: the "$id" label floats away from its icon',
          );
          expect(
            labelRect.bottom,
            lessThanOrEqualTo(rowRect.bottom + 0.5),
            reason:
                '$label: the "$id" label is clipped by its row '
                '(${labelRect.bottom.toStringAsFixed(1)} > '
                '${rowRect.bottom.toStringAsFixed(1)})',
          );
          expect(
            iconRect.top,
            greaterThanOrEqualTo(rowRect.top - 0.5),
            reason: '$label: the "$id" icon is lifted out of its row',
          );

          // The label keeps its requested size (no clamping to the old slot).
          final paragraph = tester.renderObject<RenderParagraph>(labelFinder);
          final painter = TextPainter(
            text: TextSpan(
              text: paragraph.text.toPlainText(),
              style: paragraph.text.style,
            ),
            textDirection: TextDirection.ltr,
            textScaler: paragraph.textScaler,
            maxLines: 1,
          )..layout();
          final needed = painter.height;
          painter.dispose();
          expect(
            paragraph.size.height,
            greaterThanOrEqualTo(needed - 0.5),
            reason:
                '$label: the "$id" label needs ${needed.toStringAsFixed(1)}px '
                'but got ${paragraph.size.height.toStringAsFixed(1)}px',
          );
        }
        expect(checked, greaterThan(0), reason: '$label: no labelled tab');
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('default geometry: 1x row keeps its padding and pill centre', (
    tester,
  ) async {
    _useViewport(tester, const Size(390, 780));
    final router = _router();
    addTearDown(router.dispose);
    final semantics = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        _subject(
          router: router,
          textScaler: const PrismTextScaler(TextScaler.noScaling, 1.0),
        ),
      );
      await tester.pumpAndSettle();

      final labelFinder = find.byKey(const ValueKey('nav_label_home'));
      final iconFinder = find.byKey(const ValueKey('nav_icon_slot_home'));
      expect(labelFinder, findsOneWidget);
      expect(iconFinder, findsOneWidget);

      final rowRect = _rowRect(tester, labelFinder);
      final labelRect = tester.getRect(labelFinder);
      final iconRect = tester.getRect(iconFinder);

      expect(rowRect.height, lessThanOrEqualTo(70));
      expect(rowRect.bottom - labelRect.bottom, greaterThanOrEqualTo(2.0));
      expect(labelRect.top, greaterThanOrEqualTo(iconRect.bottom - 1.0));

      final pill = tester.getRect(
        find.byKey(const ValueKey('nav_selected_pill')),
      );
      expect(
        (pill.center.dy - iconRect.center.dy).abs(),
        lessThanOrEqualTo(1.5),
        reason: 'the selected pill stays centred on the icon',
      );
    } finally {
      semantics.dispose();
    }
  });

  for (final (label, scaler) in const [
    ('large text 1.5x', PrismTextScaler(TextScaler.linear(1.5), 1.0)),
    (
      'system 225% x Prism 150% = 3.375x',
      PrismTextScaler(TextScaler.linear(2.25), 1.5),
    ),
  ]) {
    testWidgets('revealed labels keep the icon inside its row ($label)', (
      tester,
    ) async {
      _useViewport(tester, const Size(390, 780));
      final router = _router();
      addTearDown(router.dispose);
      final semantics = tester.ensureSemantics();

      try {
        await tester.pumpWidget(
          _subject(
            router: router,
            textScaler: scaler,
            labelVisibility: NavBarLabelVisibility.whenExpanded,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$label: layout error');

        final iconFinder = find.byKey(const ValueKey('nav_icon_slot_home'));
        if (iconFinder.evaluate().isEmpty) return; // overflowed at this size
        final iconRect = tester.getRect(iconFinder);
        final rowRect = tester.getRect(
          find.ancestor(of: iconFinder, matching: find.byType(Stack)).first,
        );
        expect(
          iconRect.top,
          greaterThanOrEqualTo(rowRect.top - 0.5),
          reason: '$label: the icon is lifted out of its row',
        );

        final pill = tester.getRect(
          find.byKey(const ValueKey('nav_selected_pill')),
        );
        expect(
          (pill.center.dy - iconRect.center.dy).abs(),
          lessThanOrEqualTo(1.5),
          reason: '$label: the selected pill stays centred on the icon',
        );
      } finally {
        semantics.dispose();
      }
    });
  }
}
