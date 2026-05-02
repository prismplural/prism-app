import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/services/period_delete.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

import '../../../helpers/fake_repositories.dart';

// A [FakeFrontingSessionRepository] variant whose [deleteSession] throws on a
// specific id so we can test the partial-failure path.
class _ThrowingFakeFrontingSessionRepository
    extends FakeFrontingSessionRepository {
  _ThrowingFakeFrontingSessionRepository({required this.throwOnId});

  final String throwOnId;

  @override
  Future<void> deleteSession(String id) async {
    if (id == throwOnId) {
      throw Exception('simulated delete failure');
    }
    return super.deleteSession(id);
  }
}

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026, 1, 1));

/// Builds a minimal widget harness that triggers [confirmAndDeletePeriod] when
/// tapped, stores the result in [resultHolder], and provides [repo] as the
/// [frontingSessionRepositoryProvider] override.
Widget _harness({
  required FakeFrontingSessionRepository repo,
  required List<String> sessionIds,
  required List<Member> contributors,
  required List<bool?> resultHolder,
}) {
  return ProviderScope(
    overrides: [
      frontingSessionRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: PrismToastHost(
        child: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () async {
              final result = await confirmAndDeletePeriod(
                context,
                ref,
                sessionIds: sessionIds,
                contributors: contributors,
              );
              resultHolder.add(result);
            },
            child: const Text('Delete Period'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('confirmAndDeletePeriod', () {
    tearDown(PrismToast.resetForTest);

    testWidgets(
      'user confirms → all sessions deleted, returns true',
      (tester) async {
        final repo = FakeFrontingSessionRepository();
        final resultHolder = <bool?>[];

        await tester.pumpWidget(
          _harness(
            repo: repo,
            sessionIds: const ['s1', 's2'],
            contributors: [_member('m1', 'Alice'), _member('m2', 'Bob')],
            resultHolder: resultHolder,
          ),
        );

        // Trigger the helper.
        await tester.tap(find.text('Delete Period'));
        await tester.pumpAndSettle();

        // The confirm dialog should be visible.
        expect(find.text('Delete period?'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);

        // Tap the confirm button.
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        // Helper should have returned true and both ids should be deleted.
        expect(resultHolder, [true]);
        expect(repo.deletedIds, containsAll(['s1', 's2']));
        expect(repo.deletedIds.length, 2);
      },
    );

    testWidgets(
      'user cancels → no deletes, returns false',
      (tester) async {
        final repo = FakeFrontingSessionRepository();
        final resultHolder = <bool?>[];

        await tester.pumpWidget(
          _harness(
            repo: repo,
            sessionIds: const ['s1', 's2'],
            contributors: [_member('m1', 'Alice')],
            resultHolder: resultHolder,
          ),
        );

        await tester.tap(find.text('Delete Period'));
        await tester.pumpAndSettle();

        expect(find.text('Delete period?'), findsOneWidget);

        // Tap cancel.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(resultHolder, [false]);
        expect(repo.deletedIds, isEmpty);
      },
    );

    testWidgets(
      'second deleteSession throws → stops at failed id, shows toast, returns false',
      (tester) async {
        // 's2' is the one that throws. 's1' should succeed first.
        final repo = _ThrowingFakeFrontingSessionRepository(throwOnId: 's2');
        final resultHolder = <bool?>[];

        await tester.pumpWidget(
          _harness(
            repo: repo,
            sessionIds: const ['s1', 's2'],
            contributors: [_member('m1', 'Alice'), _member('m2', 'Bob')],
            resultHolder: resultHolder,
          ),
        );

        await tester.tap(find.text('Delete Period'));
        await tester.pumpAndSettle();

        // Confirm deletion.
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        // Helper returns false on failure.
        expect(resultHolder, [false]);

        // Only 's1' was deleted before the error.
        expect(repo.deletedIds, ['s1']);
        expect(repo.deletedIds, isNot(contains('s2')));

        // A toast should be displayed with an error message.
        expect(
          find.textContaining('Error saving session'),
          findsOneWidget,
        );

        // Dismiss the toast so the auto-dismiss timer doesn't leak into
        // the next test (the timer is a 4-second FakeAsync timer).
        PrismToast.dismiss();
        await tester.pump();
      },
    );
  });
}
