import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_one_shot_push_service.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_push_new_member_dialog.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakePkOneShotPushService implements PkOneShotPushService {
  _FakePkOneShotPushService();

  final List<String> pushed = [];
  Duration? delay;
  Object? errorToThrow;
  Completer<void>? gate;

  @override
  Future<PKMember> pushSingleMember(String memberId) async {
    pushed.add(memberId);
    if (gate != null) {
      await gate!.future;
    }
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }
    if (errorToThrow != null) throw errorToThrow!;
    return PKMember(id: 'pk-$memberId', name: memberId, uuid: 'uuid-$memberId');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected call to ${invocation.memberName}');
}

class _FakeMemberRepository implements MemberRepository {
  _FakeMemberRepository(this._members);

  final Map<String, Member> _members;
  final List<Member> updates = [];
  final List<String> excluded = [];

  @override
  Future<Member?> getMemberById(String id) async => _members[id];

  @override
  Future<void> updateMember(Member member) async {
    updates.add(member);
    _members[member.id] = member;
  }

  @override
  Future<int> excludePluralKitSync(String id) async {
    excluded.add(id);
    final existing = _members[id];
    if (existing == null) return 0;
    final updated = existing.copyWith(pluralkitSyncIgnored: true);
    _members[id] = updated;
    updates.add(updated);
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected call to ${invocation.memberName}');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Member _member({String id = 'm-1', String name = 'Alice'}) =>
    Member(id: id, name: name, createdAt: DateTime.utc(2026, 1, 1));

Widget _harness({
  required _FakePkOneShotPushService pushService,
  required _FakeMemberRepository repo,
  required void Function(bool? result) onResult,
  String memberId = 'm-1',
  String memberName = 'Alice',
}) {
  return ProviderScope(
    overrides: [
      pkOneShotPushServiceProvider.overrideWithValue(pushService),
      memberRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showPkPushNewMemberDialog(
                context,
                memberId: memberId,
                memberName: memberName,
              );
              onResult(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(PrismToast.resetForTest);

  testWidgets(
    '"Push once" calls the fake one-shot service and resolves with true',
    (tester) async {
      final push = _FakePkOneShotPushService();
      final repo = _FakeMemberRepository({'m-1': _member()});
      bool? result;
      bool resolved = false;

      await tester.pumpWidget(
        _harness(
          pushService: push,
          repo: repo,
          onResult: (r) {
            result = r;
            resolved = true;
          },
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Push Alice to PluralKit?'), findsOneWidget);
      expect(find.text('Push once'), findsOneWidget);

      await tester.tap(find.text('Push once'));
      await tester.pumpAndSettle();

      expect(push.pushed, ['m-1']);
      expect(resolved, isTrue);
      expect(result, isTrue);

      // Drain the PrismToast auto-dismiss timer (3s for success, 4s for error)
      // so the test ends without "Timer is still pending" framework errors.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    '"Keep local" sets pluralkitSyncIgnored on the member and resolves with false',
    (tester) async {
      final push = _FakePkOneShotPushService();
      final repo = _FakeMemberRepository({'m-1': _member()});
      bool? result;
      bool resolved = false;

      await tester.pumpWidget(
        _harness(
          pushService: push,
          repo: repo,
          onResult: (r) {
            result = r;
            resolved = true;
          },
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Keep local'), findsOneWidget);

      await tester.tap(find.text('Keep local'));
      await tester.pumpAndSettle();

      expect(push.pushed, isEmpty);
      expect(repo.updates, hasLength(1));
      expect(repo.updates.single.id, 'm-1');
      expect(repo.updates.single.pluralkitSyncIgnored, isTrue);
      // PR 2 Part 1.7 site 10: routes through excludePluralKitSync (NOT
      // generic updateMember). The fake records the call directly.
      expect(
        repo.excluded,
        ['m-1'],
        reason: '"Keep local" must route through excludePluralKitSync',
      );
      expect(resolved, isTrue);
      expect(result, isFalse);
    },
  );

  testWidgets('backdrop dismiss resolves with null', (tester) async {
    final push = _FakePkOneShotPushService();
    final repo = _FakeMemberRepository({'m-1': _member()});
    bool? result;
    bool resolved = false;

    await tester.pumpWidget(
      _harness(
        pushService: push,
        repo: repo,
        onResult: (r) {
          result = r;
          resolved = true;
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Push Alice to PluralKit?'), findsOneWidget);

    // Tap on the modal barrier outside the dialog (top-left corner of screen).
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Push Alice to PluralKit?'), findsNothing);
    expect(push.pushed, isEmpty);
    expect(repo.updates, isEmpty);
    expect(resolved, isTrue);
    expect(result, isNull);
  });

  testWidgets('push failure does NOT pop with true and keeps the dialog open', (
    tester,
  ) async {
    final push = _FakePkOneShotPushService()..errorToThrow = StateError('nope');
    final repo = _FakeMemberRepository({'m-1': _member()});
    bool? result;
    bool resolved = false;

    await tester.pumpWidget(
      _harness(
        pushService: push,
        repo: repo,
        onResult: (r) {
          result = r;
          resolved = true;
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push once'));
    await tester.pumpAndSettle();

    expect(push.pushed, ['m-1']);
    // Dialog should still be visible (not popped with true).
    expect(find.text('Push Alice to PluralKit?'), findsOneWidget);
    expect(resolved, isFalse);
    expect(result, isNull);

    // Drain the PrismToast error auto-dismiss timer (4s).
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('loading state disables both buttons while push is in-flight', (
    tester,
  ) async {
    final push = _FakePkOneShotPushService();
    final gate = Completer<void>();
    push.gate = gate;
    final repo = _FakeMemberRepository({'m-1': _member()});

    await tester.pumpWidget(
      _harness(pushService: push, repo: repo, onResult: (_) {}),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push once'));
    await tester.pump(); // start async, mark busy
    await tester.pump();

    // While in-flight, the "Push once" button replaces its label with a
    // spinner (so `find.text('Push once')` no longer matches inside it);
    // identify the two buttons by inspecting all PrismButton widgets.
    final allButtons = tester
        .widgetList<PrismButton>(find.byType(PrismButton))
        .where((b) => b.label == 'Push once' || b.label == 'Keep local')
        .toList();
    // ElevatedButton from the harness is NOT a PrismButton, so we only
    // see the dialog's two buttons here.
    expect(allButtons, hasLength(2));
    final pushButton = allButtons.firstWhere((b) => b.label == 'Push once');
    final keepLocalButton = allButtons.firstWhere(
      (b) => b.label == 'Keep local',
    );
    expect(pushButton.enabled, isFalse);
    expect(pushButton.isLoading, isTrue);
    expect(keepLocalButton.enabled, isFalse);

    // Let the push finish so pump completes.
    gate.complete();
    await tester.pumpAndSettle();

    // Drain the PrismToast success auto-dismiss timer (3s).
    await tester.pump(const Duration(seconds: 5));
  });
}
