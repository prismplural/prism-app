// Tests for the wake-up-as picker in FrontingScreen.
//
// The picker is invoked via the private _showWakeUpPicker method on
// _AddButtonState. Since that is not directly callable from outside the
// library, the tests use a thin ConsumerStatefulWidget harness that mirrors
// the exact logic the method will execute after the MemberSearchSheet
// migration.  This lets us verify:
//   1. The shared single-select sheet (MemberSearchSheet) is shown.
//   2. Selecting a member ends the sleep session then starts fronting.
//   3. Dismissing the sheet does not trigger the wake-up flow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test doubles
// ─────────────────────────────────────────────────────────────────────────────

class _FakeSleepNotifier extends SleepNotifier {
  final List<String> endedIds = [];

  @override
  void build() {}

  @override
  Future<void> endSleep(String id) async => endedIds.add(id);
}

class _FakeFrontingNotifier extends FrontingNotifier {
  final List<String> startedIds = [];

  @override
  Future<void> build() async {}

  @override
  Future<void> startFronting(
    String memberId, {
    List<String> coFronterIds = const [],
  }) async => startedIds.add(memberId);
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2024));

FrontingSession _sleepSession() => FrontingSession(
  id: 'sleep-1',
  startTime: DateTime(2024),
  sessionType: SessionType.sleep,
);

/// Minimal harness that mirrors the logic of _showWakeUpPicker after the
/// MemberSearchSheet migration.  A tap on the "Wake up as" button triggers
/// the same async flow the production method will use.
class _WakeUpPickerHarness extends ConsumerStatefulWidget {
  const _WakeUpPickerHarness({
    required this.sleepSession,
    required this.members,
  });

  final FrontingSession sleepSession;
  final List<Member> members;

  @override
  ConsumerState<_WakeUpPickerHarness> createState() =>
      _WakeUpPickerHarnessState();
}

class _WakeUpPickerHarnessState extends ConsumerState<_WakeUpPickerHarness> {
  Future<void> _showPicker() async {
    final session = widget.sleepSession;
    final result = await MemberSearchSheet.showSingle(
      context,
      members: widget.members,
      termPlural: 'Members',
    );

    if (!mounted || !context.mounted) return;
    if (result is! MemberSearchResultSelected) return;
    final activeSession = ref.read(activeSleepSessionProvider).value;
    if (activeSession?.id != session.id) return;

    try {
      await ref.read(sleepNotifierProvider.notifier).endSleep(session.id);
      await ref
          .read(frontingNotifierProvider.notifier)
          .startFronting(result.memberId);
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(context, message: 'error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(activeSleepSessionProvider);
    return ElevatedButton(
      onPressed: _showPicker,
      child: const Text('Wake up as'),
    );
  }
}

Widget _buildSubject({
  required _FakeSleepNotifier sleepNotifier,
  required _FakeFrontingNotifier frontingNotifier,
  List<Member>? members,
  FrontingSession? activeSleepSession,
}) {
  final ms = members ?? [_member('m1', 'Alice'), _member('m2', 'Bob')];
  final sleep = activeSleepSession ?? _sleepSession();
  return ProviderScope(
    overrides: [
      sleepNotifierProvider.overrideWith(() => sleepNotifier),
      frontingNotifierProvider.overrideWith(() => frontingNotifier),
      activeSleepSessionProvider.overrideWith((ref) => Stream.value(sleep)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: _WakeUpPickerHarness(sleepSession: _sleepSession(), members: ms),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('wake-up picker', () {
    testWidgets('tapping Wake up as opens the shared single-select sheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(
          sleepNotifier: _FakeSleepNotifier(),
          frontingNotifier: _FakeFrontingNotifier(),
        ),
      );

      await tester.tap(find.text('Wake up as'));
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
    });

    testWidgets('selecting a member ends sleep then starts fronting', (
      tester,
    ) async {
      final sleep = _FakeSleepNotifier();
      final fronting = _FakeFrontingNotifier();

      await tester.pumpWidget(
        _buildSubject(sleepNotifier: sleep, frontingNotifier: fronting),
      );

      await tester.tap(find.text('Wake up as'));
      await tester.pumpAndSettle();

      // Tap the first member row in the search sheet.
      await tester.tap(find.text('Alice').last);
      await tester.pumpAndSettle();

      expect(
        sleep.endedIds,
        ['sleep-1'],
        reason: 'endSleep must be called with the sleep session id',
      );
      expect(
        fronting.startedIds,
        ['m1'],
        reason: 'startFronting must be called with the selected member id',
      );
    });

    testWidgets('dismissing the sheet does not trigger the wake-up flow', (
      tester,
    ) async {
      final sleep = _FakeSleepNotifier();
      final fronting = _FakeFrontingNotifier();

      await tester.pumpWidget(
        _buildSubject(sleepNotifier: sleep, frontingNotifier: fronting),
      );

      await tester.tap(find.text('Wake up as'));
      await tester.pumpAndSettle();

      // Close via the X button in the sheet's top bar.
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();

      expect(
        sleep.endedIds,
        isEmpty,
        reason: 'endSleep must not be called on dismiss',
      );
      expect(
        fronting.startedIds,
        isEmpty,
        reason: 'startFronting must not be called on dismiss',
      );
    });

    testWidgets('does not end sleep after active sleep session changes', (
      tester,
    ) async {
      final sleep = _FakeSleepNotifier();
      final fronting = _FakeFrontingNotifier();

      await tester.pumpWidget(
        _buildSubject(
          sleepNotifier: sleep,
          frontingNotifier: fronting,
          activeSleepSession: FrontingSession(
            id: 'other-sleep',
            startTime: DateTime(2024),
            sessionType: SessionType.sleep,
          ),
        ),
      );

      await tester.tap(find.text('Wake up as'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice').last);
      await tester.pumpAndSettle();

      expect(sleep.endedIds, isEmpty);
      expect(fronting.startedIds, isEmpty);
    });
  });
}
