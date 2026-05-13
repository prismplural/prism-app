import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_unpushed_members_notice.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_unpushed_members_notice_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_one_shot_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_unpushed_members_notice.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _RecordedApply {
  _RecordedApply({
    required this.members,
    required this.pkReady,
    required this.pushDisabled,
  });

  final List<Member> members;
  final bool pkReady;
  final bool pushDisabled;
}

class _FakeNoticeController extends PkUnpushedMembersNoticeController {
  _FakeNoticeController({PkUnpushedMembersNoticeState? initial})
    : _initial = initial ?? const PkUnpushedMembersNoticeState();

  final PkUnpushedMembersNoticeState _initial;
  final List<_RecordedApply> applyCalls = [];
  final List<PkUnpushedMembersNotice> dismissed = [];
  int clearCount = 0;

  @override
  Future<PkUnpushedMembersNoticeState> build() async => _initial;

  @override
  Future<void> applyMembersSnapshot(
    List<Member> members, {
    required bool pkReady,
    required bool pushDisabled,
  }) async {
    applyCalls.add(
      _RecordedApply(
        members: List<Member>.unmodifiable(members),
        pkReady: pkReady,
        pushDisabled: pushDisabled,
      ),
    );
  }

  @override
  Future<void> dismiss(PkUnpushedMembersNotice notice) async {
    dismissed.add(notice);
    final current = state.value ?? _initial;
    state = AsyncValue.data(
      current.copyWith(
        clearCurrentNotice:
            current.currentNotice?.dismissalKey == notice.dismissalKey,
      ),
    );
  }

  @override
  Future<void> clear() async {
    clearCount++;
    final current = state.value ?? _initial;
    state = AsyncValue.data(current.copyWith(clearCurrentNotice: true));
  }
}

class _FakePkOneShotPushService implements PkOneShotPushService {
  final List<String> pushed = [];
  Object? errorToThrow;

  @override
  Future<PKMember> pushSingleMember(String memberId) async {
    pushed.add(memberId);
    if (errorToThrow != null) throw errorToThrow!;
    return PKMember(
      id: 'pk-$memberId',
      name: memberId,
      uuid: 'uuid-$memberId',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected call to ${invocation.memberName}');
}

class _FakeMemberRepository implements MemberRepository {
  _FakeMemberRepository(this._members);

  final Map<String, Member> _members;
  final List<Member> updates = [];

  @override
  Future<Member?> getMemberById(String id) async => _members[id];

  @override
  Future<void> updateMember(Member member) async {
    updates.add(member);
    _members[member.id] = member;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected call to ${invocation.memberName}');
}

class _StaticPkSyncDirectionNotifier extends PkSyncDirectionNotifier {
  _StaticPkSyncDirectionNotifier(this._direction);

  PkSyncDirection _direction;

  @override
  PkSyncDirection build() => _direction;

  @override
  Future<void> load() async {
    state = _direction;
  }

  void setForTest(PkSyncDirection direction) {
    _direction = direction;
    state = direction;
  }
}

class _StaticPkSyncModeNotifier extends PkSyncModeNotifier {
  _StaticPkSyncModeNotifier(this._mode);

  final PkSyncMode _mode;

  @override
  PkSyncMode build() => _mode;

  @override
  Future<void> load() async {
    state = _mode;
  }
}

class _StaticPluralKitSyncNotifier extends PluralKitSyncNotifier {
  _StaticPluralKitSyncNotifier(this._state);

  final PluralKitSyncState _state;

  @override
  PluralKitSyncState build() => _state;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Member _member({
  required String id,
  String name = 'Member',
  String? displayName,
  String? pluralkitId,
  String? pluralkitUuid,
  bool pluralkitSyncIgnored = false,
  bool isDeleted = false,
}) {
  return Member(
    id: id,
    name: name,
    displayName: displayName,
    emoji: '❔',
    isActive: true,
    createdAt: DateTime.utc(2026, 1, 1),
    pluralkitId: pluralkitId,
    pluralkitUuid: pluralkitUuid,
    pluralkitSyncIgnored: pluralkitSyncIgnored,
    isDeleted: isDeleted,
  );
}

PluralKitSyncState _readyState() => const PluralKitSyncState(
  isConnected: true,
  directionConfirmed: true,
  mappingAcknowledged: true,
);

Widget _wrap({
  required Widget child,
  required _FakeNoticeController controller,
  required _FakePkOneShotPushService pushService,
  required _FakeMemberRepository repo,
  List<Member> members = const <Member>[],
  PluralKitSyncState? syncState,
  PkSyncDirection direction = PkSyncDirection.pullOnly,
  PkSyncMode mode = PkSyncMode.liveFrontsOnly,
  bool writesBlocked = false,
}) {
  return ProviderScope(
    overrides: [
      pkUnpushedMembersNoticeProvider.overrideWith(() => controller),
      pkOneShotPushServiceProvider.overrideWithValue(pushService),
      memberRepositoryProvider.overrideWithValue(repo),
      allMembersProvider.overrideWith((ref) => Stream.value(members)),
      pluralKitSyncProvider.overrideWith(
        () => _StaticPluralKitSyncNotifier(syncState ?? _readyState()),
      ),
      pkSyncDirectionProvider.overrideWith(
        () => _StaticPkSyncDirectionNotifier(direction),
      ),
      pkSyncModeProvider.overrideWith(() => _StaticPkSyncModeNotifier(mode)),
      frontingMigrationWritesBlockedProvider.overrideWithValue(writesBlocked),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: child),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeNoticeController controller;
  late _FakePkOneShotPushService pushService;
  late _FakeMemberRepository repo;

  setUp(() {
    controller = _FakeNoticeController();
    pushService = _FakePkOneShotPushService();
    repo = _FakeMemberRepository({});
    PrismToast.resetForTest();
  });

  testWidgets(
    'banner is not rendered when there is no current notice',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          controller: controller,
          pushService: pushService,
          repo: repo,
          child: const PluralKitUnpushedMembersNoticeBanner(),
        ),
      );
      await tester.pump();

      expect(find.text('Local members not on PluralKit'), findsNothing);
      expect(find.byType(PluralKitUnpushedMembersNoticeBanner), findsOneWidget);
    },
  );

  testWidgets(
    'on mount, applyMembersSnapshot fires with correct inputs',
    (tester) async {
      final m1 = _member(id: 'm-1', name: 'Alice');
      final m2 = _member(id: 'm-2', name: 'Bob');

      await tester.pumpWidget(
        _wrap(
          controller: controller,
          pushService: pushService,
          repo: _FakeMemberRepository({'m-1': m1, 'm-2': m2}),
          members: [m1, m2],
          direction: PkSyncDirection.pullOnly,
          mode: PkSyncMode.liveFrontsOnly,
          child: const PluralKitUnpushedMembersNoticeBanner(),
        ),
      );
      // initState fires listenManual + post-frame eager recompute.
      await tester.pump();
      await tester.pump();

      expect(controller.applyCalls, isNotEmpty);
      final call = controller.applyCalls.first;
      expect(call.members.map((m) => m.id), ['m-1', 'm-2']);
      expect(call.pkReady, isTrue);
      // pushOnly direction has pushEnabled=true but mode liveFrontsOnly
      // forces pushDisabled true. pullOnly has pushEnabled=false → also true.
      expect(call.pushDisabled, isTrue);
    },
  );

  testWidgets(
    'flipping pkSyncDirection triggers a recompute with pushDisabled=false',
    (tester) async {
      final m1 = _member(id: 'm-1', name: 'Alice');
      final directionNotifier = _StaticPkSyncDirectionNotifier(
        PkSyncDirection.pullOnly,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pkUnpushedMembersNoticeProvider.overrideWith(() => controller),
            pkOneShotPushServiceProvider.overrideWithValue(pushService),
            memberRepositoryProvider.overrideWithValue(
              _FakeMemberRepository({'m-1': m1}),
            ),
            allMembersProvider.overrideWith((ref) => Stream.value([m1])),
            pluralKitSyncProvider.overrideWith(
              () => _StaticPluralKitSyncNotifier(_readyState()),
            ),
            pkSyncDirectionProvider.overrideWith(() => directionNotifier),
            pkSyncModeProvider.overrideWith(
              () => _StaticPkSyncModeNotifier(PkSyncMode.fullSync),
            ),
            frontingMigrationWritesBlockedProvider.overrideWithValue(false),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: [Locale('en')],
            home: Scaffold(body: PluralKitUnpushedMembersNoticeBanner()),
          ),
        ),
      );
      // initState + post-frame callback fires the first apply.
      await tester.pump();
      await tester.pump();
      expect(controller.applyCalls, isNotEmpty);
      final firstCall = controller.applyCalls.last;
      // pullOnly => push disabled
      expect(firstCall.pushDisabled, isTrue);

      // Flip direction in-place — banner's listenManual should fire.
      directionNotifier.setForTest(PkSyncDirection.bidirectional);
      await tester.pump();
      await tester.pump();

      expect(controller.applyCalls.length, greaterThan(1));
      final lastCall = controller.applyCalls.last;
      expect(lastCall.pushDisabled, isFalse);
    },
  );

  testWidgets('"Push once" calls the fake one-shot service', (tester) async {
    final m1 = _member(id: 'm-1', name: 'Alice');
    controller = _FakeNoticeController(
      initial: const PkUnpushedMembersNoticeState(
        currentNotice: PkUnpushedMembersNotice(
          refs: [PkUnpushedMemberRef(memberId: 'm-1', memberName: 'Alice')],
        ),
      ),
    );

    await tester.pumpWidget(
      _wrap(
        controller: controller,
        pushService: pushService,
        repo: _FakeMemberRepository({'m-1': m1}),
        members: [m1],
        child: const PluralKitUnpushedMembersNoticeBanner(),
      ),
    );
    await tester.pump();

    expect(find.text('Local members not on PluralKit'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Push once'), findsOneWidget);
    await tester.tap(find.text('Push once'));
    await tester.pumpAndSettle();

    expect(pushService.pushed, ['m-1']);

    // Drain PrismToast.success auto-dismiss timer (3s) so the test tear-down
    // does not see a pending Timer.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
    '"Keep local" sets pluralkitSyncIgnored on the member',
    (tester) async {
      final m1 = _member(id: 'm-1', name: 'Alice');
      final localRepo = _FakeMemberRepository({'m-1': m1});
      controller = _FakeNoticeController(
        initial: const PkUnpushedMembersNoticeState(
          currentNotice: PkUnpushedMembersNotice(
            refs: [PkUnpushedMemberRef(memberId: 'm-1', memberName: 'Alice')],
          ),
        ),
      );

      await tester.pumpWidget(
        _wrap(
          controller: controller,
          pushService: pushService,
          repo: localRepo,
          members: [m1],
          child: const PluralKitUnpushedMembersNoticeBanner(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.text('Keep local'), findsOneWidget);
      await tester.tap(find.text('Keep local'));
      await tester.pumpAndSettle();

      expect(localRepo.updates, hasLength(1));
      expect(localRepo.updates.single.id, 'm-1');
      expect(localRepo.updates.single.pluralkitSyncIgnored, isTrue);

      // Drain PrismToast.success auto-dismiss timer (3s).
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('"Dismiss for now" calls dismiss(notice)', (tester) async {
    final m1 = _member(id: 'm-1', name: 'Alice');
    const notice = PkUnpushedMembersNotice(
      refs: [PkUnpushedMemberRef(memberId: 'm-1', memberName: 'Alice')],
    );
    controller = _FakeNoticeController(
      initial: const PkUnpushedMembersNoticeState(currentNotice: notice),
    );

    await tester.pumpWidget(
      _wrap(
        controller: controller,
        pushService: pushService,
        repo: _FakeMemberRepository({'m-1': m1}),
        members: [m1],
        child: const PluralKitUnpushedMembersNoticeBanner(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Dismiss for now'), findsOneWidget);
    await tester.tap(find.text('Dismiss for now'));
    await tester.pumpAndSettle();

    expect(controller.dismissed, hasLength(1));
    expect(controller.dismissed.single.dismissalKey, notice.dismissalKey);
  });
}
