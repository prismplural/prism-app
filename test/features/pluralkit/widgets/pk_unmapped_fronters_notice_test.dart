import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_live_fronters_notice.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_unmapped_fronters_notice_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_unmapped_fronters_notice.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

final _events = <String>[];

final _notice = PkUnmappedFrontersNotice(
  systemId: 'sys-1',
  switchId: 'switch-1',
  switchTimestamp: DateTime.utc(2026, 5, 11, 12),
  sortedPkIds: const ['abcde'],
  refs: const [
    PkUnmappedFronterRef(
      pkId: 'abcde',
      pkUuid: 'pk-uuid-1',
      name: 'River',
      displayName: 'River PK',
    ),
  ],
);

final _changedNotice = PkUnmappedFrontersNotice(
  systemId: 'sys-1',
  switchId: 'switch-2',
  switchTimestamp: DateTime.utc(2026, 5, 11, 12, 5),
  sortedPkIds: const ['abcde'],
  refs: const [
    PkUnmappedFronterRef(
      pkId: 'abcde',
      pkUuid: 'pk-uuid-1',
      name: 'River',
      displayName: 'River PK',
    ),
  ],
);

final _localMember = Member(
  id: 'member-1',
  name: 'River Local',
  createdAt: DateTime(2024),
);

class _FakeNoticeController extends PkUnmappedFrontersNoticeController {
  static PkUnmappedFrontersNoticeState initial =
      const PkUnmappedFrontersNoticeState();
  static final calls = <String>[];

  @override
  Future<PkUnmappedFrontersNoticeState> build() async => initial;

  @override
  Future<void> publish(PkUnmappedFrontersNotice notice) async {
    final current = state.value ?? initial;
    state = AsyncValue.data(current.copyWith(currentNotice: notice));
  }

  @override
  Future<void> dismiss(PkUnmappedFrontersNotice notice) async {
    calls.add('skip');
    final current = state.value ?? initial;
    state = AsyncValue.data(
      current.copyWith(
        clearCurrentNotice:
            current.currentNotice?.dismissalKey == notice.dismissalKey,
      ),
    );
  }

  @override
  Future<void> clear() async {
    _events.add('clear');
    final current = state.value ?? initial;
    state = AsyncValue.data(current.copyWith(clearCurrentNotice: true));
  }
}

class _FakePluralKitSyncNotifier extends PluralKitSyncNotifier {
  static final directions = <PkSyncDirection>[];
  static final manualFlags = <bool>[];
  static final noticesAfterSync = <PkUnmappedFrontersNotice?>[];

  @override
  PluralKitSyncState build() => const PluralKitSyncState(isConnected: true);

  @override
  Future<PkSyncSummary?> syncLiveFrontersOnly({
    bool isManual = false,
    PkSyncDirection direction = PkSyncDirection.pullOnly,
    PKSwitch? knownCurrentFronters,
  }) async {
    directions.add(direction);
    manualFlags.add(isManual);
    _events.add('sync:${direction.name}');

    final notice = noticesAfterSync.isEmpty
        ? null
        : noticesAfterSync.removeAt(0);
    if (notice != null) {
      await ref.read(pkUnmappedFrontersNoticeProvider.notifier).publish(notice);
      return PkSyncSummary(
        liveUnmappedFronters: notice,
        observedLiveFronters: true,
        observedLiveFrontersDismissalKey: notice.dismissalKey,
      );
    }

    final currentNotice = ref
        .read(pkUnmappedFrontersNoticeProvider)
        .whenOrNull(data: (state) => state.currentNotice);
    return PkSyncSummary(
      observedLiveFronters: true,
      observedLiveFrontersDismissalKey: currentNotice?.dismissalKey,
    );
  }
}

class _FakePluralKitSyncService implements PluralKitSyncService {
  final importedRefs = <PkUnmappedFronterRef>[];

  @override
  Future<Member> importCurrentFronter(
    PkUnmappedFronterRef ref, {
    bool includeAvatar = false,
  }) async {
    _events.add('write:${ref.pkId}');
    importedRefs.add(ref);
    return _localMember;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected call to ${invocation.memberName}');
}

Widget _wrap({
  required Widget child,
  bool writesBlocked = false,
  List<Member> members = const <Member>[],
  _FakePluralKitSyncService? syncService,
}) {
  return ProviderScope(
    overrides: [
      pkUnmappedFrontersNoticeProvider.overrideWith(_FakeNoticeController.new),
      pluralKitSyncProvider.overrideWith(_FakePluralKitSyncNotifier.new),
      pluralKitSyncServiceProvider.overrideWithValue(
        syncService ?? _FakePluralKitSyncService(),
      ),
      frontingMigrationWritesBlockedProvider.overrideWithValue(writesBlocked),
      userVisibleMembersProvider.overrideWithValue(AsyncValue.data(members)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    _events.clear();
    _FakeNoticeController.calls.clear();
    _FakeNoticeController.initial = PkUnmappedFrontersNoticeState(
      currentNotice: _notice,
    );
    _FakePluralKitSyncNotifier.directions.clear();
    _FakePluralKitSyncNotifier.manualFlags.clear();
    _FakePluralKitSyncNotifier.noticesAfterSync.clear();
  });

  testWidgets('shows review banner and sheet actions for unmapped fronters', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        members: [_localMember],
        child: const PluralKitUnmappedFrontersNoticeBanner(),
      ),
    );
    await tester.pump();

    expect(find.text('PluralKit front change needs review'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Review PluralKit front change'), findsOneWidget);
    expect(find.text('River PK'), findsOneWidget);
    expect(find.text('Import to Prism'), findsOneWidget);
    expect(find.text('Link existing member'), findsOneWidget);
    expect(find.text('Skip this front change'), findsOneWidget);

    await tester.tap(find.text('Skip this front change'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(_FakeNoticeController.calls, ['skip']);
  });

  testWidgets('disables review while migration writes are blocked', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        writesBlocked: true,
        child: const PluralKitUnmappedFrontersNoticeBanner(),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'Resolve the fronting upgrade before reviewing unmapped PluralKit fronters.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Review PluralKit front change'), findsNothing);
    expect(_FakeNoticeController.calls, isEmpty);
  });

  testWidgets(
    'import revalidates with forced pull-only before writing and retries after',
    (tester) async {
      final syncService = _FakePluralKitSyncService();
      _FakePluralKitSyncNotifier.noticesAfterSync.add(_notice);

      await tester.pumpWidget(
        _wrap(
          syncService: syncService,
          child: const PluralKitUnmappedFrontersNoticeBanner(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Import to Prism'));
      await tester.pumpAndSettle();

      expect(_FakePluralKitSyncNotifier.directions, [
        PkSyncDirection.pullOnly,
        PkSyncDirection.pullOnly,
      ]);
      expect(_FakePluralKitSyncNotifier.manualFlags, [false, false]);
      expect(syncService.importedRefs, hasLength(1));
      expect(syncService.importedRefs.single.pkId, 'abcde');
      expect(_events, [
        'sync:pullOnly',
        'write:abcde',
        'sync:pullOnly',
        'clear',
      ]);
    },
  );

  testWidgets(
    'import does not write when forced preflight sync changes notice key',
    (tester) async {
      final syncService = _FakePluralKitSyncService();
      _FakePluralKitSyncNotifier.noticesAfterSync.add(_changedNotice);

      await tester.pumpWidget(
        _wrap(
          syncService: syncService,
          child: const PluralKitUnmappedFrontersNoticeBanner(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Import to Prism'));
      await tester.pumpAndSettle();

      expect(_FakePluralKitSyncNotifier.directions, [PkSyncDirection.pullOnly]);
      expect(_FakePluralKitSyncNotifier.manualFlags, [false]);
      expect(syncService.importedRefs, isEmpty);
      expect(_events, ['sync:pullOnly']);

      // In this bailout path, the import returns null instead of taking the
      // success branch that pops the sheet via Navigator. Dismiss the sheet
      // explicitly so its modal route's barrier animation doesn't leak a
      // timer past test teardown.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    },
  );
}
