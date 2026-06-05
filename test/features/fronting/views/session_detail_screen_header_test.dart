import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/front_comments_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/views/session_detail_screen.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/providers/accessibility_preferences_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/adaptive_detail_surface.dart';
import 'package:prism_plurality/shared/widgets/detail_side_sheet.dart';

import '../../../helpers/fake_repositories.dart';

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lB0Q9wAAAABJRU5ErkJggg==',
);

FrontingSession _session({String memberId = 'member-1'}) => FrontingSession(
  id: 'session-1',
  memberId: memberId,
  startTime: DateTime(2026, 4, 30, 10),
  endTime: DateTime(2026, 4, 30, 11),
);

Member _member({bool profileHeaderVisible = true}) => Member(
  id: 'member-1',
  name: 'Alice',
  pronouns: 'she/her',
  emoji: '*',
  createdAt: DateTime(2026, 4, 30),
  profileHeaderVisible: profileHeaderVisible,
  profileHeaderImageData: _pngBytes,
);

Widget _wrap({
  required FrontingSession session,
  required Member member,
  Widget? child,
  FakeAppPreferenceRepository? appPrefs,
}) {
  return ProviderScope(
    overrides: [
      if (appPrefs != null)
        appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
      sessionByIdProvider(
        session.id,
      ).overrideWith((ref) => Stream.value(session)),
      memberByIdProvider(member.id).overrideWith((ref) => Stream.value(member)),
      activeMembersProvider.overrideWith((ref) => Stream.value([member])),
      allGroupsProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      commentsForSessionProvider(
        session.id,
      ).overrideWith((ref) => Stream.value(const [])),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: child ?? SessionDetailScreen(sessionId: session.id),
    ),
  );
}

Finder get _headerImages => find.byWidgetPredicate(
  (widget) => widget is Image && widget.semanticLabel == 'Alice profile header',
);

void main() {
  testWidgets(
    'renders visible member header as compact session detail banner',
    (tester) async {
      final session = _session();

      await tester.pumpWidget(_wrap(session: session, member: _member()));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('she/her'), findsOneWidget);
      expect(_headerImages, findsOneWidget);
      expect(find.byType(AspectRatio), findsNothing);
    },
  );

  testWidgets('respects hidden member header on session detail', (
    tester,
  ) async {
    final session = _session();

    await tester.pumpWidget(
      _wrap(session: session, member: _member(profileHeaderVisible: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('she/her'), findsOneWidget);
    expect(_headerImages, findsNothing);
  });

  testWidgets(
    'edit action from side sheet opens editor above the detail card',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 700);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final session = _session();

      await tester.pumpWidget(
        _wrap(
          session: session,
          member: _member(profileHeaderVisible: false),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDetailSideSheet(
                  context,
                  builder: (_) => SessionDetailScreen(sessionId: session.id),
                );
              },
              child: const Text('Open detail'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open detail'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detailSideSheetPanel')), findsOneWidget);

      await tester.tap(find.byIcon(AppIcons.editOutlined));
      await tester.pumpAndSettle();

      expect(find.text('Edit Session'), findsOneWidget);
      expect(find.byKey(const Key('detailSideSheetPanel')), findsNWidgets(2));
    },
  );

  testWidgets(
    'edit action from centered detail sheet opens editor above the sheet',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 700);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final session = _session();
      final prefs = FakeAppPreferenceRepository()
        ..seed(forceCenteredSheetsPreference, true);
      addTearDown(prefs.close);

      await tester.pumpWidget(
        _wrap(
          session: session,
          member: _member(profileHeaderVisible: false),
          appPrefs: prefs,
          child: _AccessibilityPreferenceWarmup(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showAdaptiveDetailSurface<void>(
                    context: context,
                    builder: (_) => SessionDetailScreen(sessionId: session.id),
                  );
                },
                child: const Text('Open detail'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Open detail'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byKey(const Key('detailSideSheetPanel')), findsNothing);

      await tester.tap(find.byIcon(AppIcons.editOutlined));
      await tester.pumpAndSettle();

      expect(find.text('Edit Session'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNWidgets(2));
      expect(find.byKey(const Key('detailSideSheetPanel')), findsNothing);
    },
  );
}

class _AccessibilityPreferenceWarmup extends ConsumerWidget {
  const _AccessibilityPreferenceWarmup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dimBackgroundBehindSheetsProvider);
    ref.watch(forceCenteredSheetsProvider);
    return child;
  }
}
