// Phase 0 parity tests for the SP-import perf work
// (`docs/plans/sp-import-perf-quick-wins.md`).
//
// Six assertions per fixture. The full plan §"Assertions" lists them; here
// they appear in the same order at the call sites so reviewers can trace
// each spec point to a concrete `expect()`.
//
// Baseline goldens are written to `golden/sp_import_baseline_*.json` on
// first run (or when `--update-goldens` is implied by env). Subsequent
// runs assert byte-equality against the saved golden.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/chat_messages_dao.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart'
    show debugDisposeOutboxDrainForTesting;
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_categories_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_board_posts_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

import 'sp_import_parity_harness.dart';

/// Set to `true` to (re)generate the baseline golden files on the next run.
/// Leave `false` for normal regression runs.
///
/// In CI we want byte-equality; locally the engineer running the harness
/// for the first time sets `PRISM_UPDATE_PARITY_GOLDENS=1`.
bool get _updateGoldens =>
    Platform.environment['PRISM_UPDATE_PARITY_GOLDENS'] == '1';

const _goldenDir = 'test/features/migration/golden';
const _fixtureDir = 'test/features/migration/fixtures';

void main() {
  group('SP import parity harness', () {
    setUp(() {
      // Each test installs its own capture sink; the global static must be
      // clean between tests so a leaked install doesn't corrupt the next
      // run.
      expect(
        SyncRecordMixin.hasCaptureSink,
        isFalse,
        reason: 'No prior test should leave the capture sink installed',
      );
    });

    test('small fixture: 6 assertions pass against golden', () async {
      await _runParity(
        fixture: 'sp_parity_small.json',
        golden: 'sp_import_baseline_small.json',
        seed: 0xA110C,
        clockMs: 1_700_500_000_000,
        unpaired: false,
        failingTx: false,
      );
    });

    test('medium fixture: 6 assertions pass against golden', () async {
      await _runParity(
        fixture: 'sp_parity_medium.json',
        golden: 'sp_import_baseline_medium.json',
        seed: 0xB220C,
        clockMs: 1_700_500_000_000,
        unpaired: false,
        failingTx: false,
      );
    });

    test('unpaired fixture: zero error reports + 6 assertions pass', () async {
      await _runParity(
        fixture: 'sp_parity_unpaired.json',
        golden: 'sp_import_baseline_unpaired.json',
        seed: 0xC330C,
        clockMs: 1_700_500_000_000,
        unpaired: true,
        failingTx: false,
      );
    });

    test(
      'failing_tx fixture: zero emissions when transaction rolls back',
      () async {
        await _runParity(
          fixture: 'sp_parity_failing_tx.json',
          golden: 'sp_import_baseline_failing_tx.json',
          seed: 0xD440C,
          clockMs: 1_700_500_000_000,
          unpaired: false,
          failingTx: true,
        );
      },
    );

    // Phase 6 fix-up (review review of 22354929):
    //
    // The `failing_tx` test above injects its failure at
    // `memberRepo.getAllMembers()` — BEFORE any batch insert runs. That
    // validates the importer never reaches the writes, but it does NOT
    // validate the actual rollback/replay contract Phase 5 was designed
    // to prove: that when SOME batches have already committed inside the
    // transaction and a LATER batch throws, the entire transaction rolls
    // back AND the local `captured` list of emissions is dropped (replay
    // loop never runs).
    //
    // This test injects the throw inside `ChatMessagesDao.batchInsertMessages`
    // — by step 9 in the importer's pipeline, members (step 1) and fronting
    // sessions (step 4) have already batch-inserted. Asserting an empty
    // snapshot + empty emissions after the throw proves the transaction
    // atomicity + `suppressAndCapture` finally-discard both hold mid-pipeline,
    // not just at the entrance.
    test(
      'mid-batch failure: zero rows + zero emissions when batchInsertMessages '
      'throws after members + sessions committed',
      () async {
        await _runMidBatchFailureParity(
          fixture: 'sp_parity_failing_tx.json',
          seed: 0xE550C,
          clockMs: 1_700_500_000_000,
        );
      },
    );
  });

  group('SP import parity harness — slow', () {
    test('large fixture: 6 assertions pass against golden', () async {
      await _runParity(
        fixture: 'sp_parity_large.json',
        golden: 'sp_import_baseline_large.json',
        seed: 0xE550C,
        clockMs: 1_700_500_000_000,
        unpaired: false,
        failingTx: false,
      );
    }, tags: ['slow']);
  });
}

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------

/// Run a fixture end-to-end through the parity harness and assert each of
/// the six properties from the plan.
///
/// Asserts (cite assertion numbers from
/// `docs/plans/sp-import-perf-quick-wins.md`, §Phase 0 §Assertions):
///   1. DB snapshot byte-equal to baseline.
///   2. Emission multiset equal to baseline.
///   3. Progress sequence equal to baseline.
///   4. (failing-tx only) zero emissions.
///   5. (unpaired only) zero error reports.
///   6. Stream-update counts ≥ baseline per table.
Future<void> _runParity({
  required String fixture,
  required String golden,
  required int seed,
  required int clockMs,
  required bool unpaired,
  required bool failingTx,
}) async {
  final fixturePath = '$_fixtureDir/$fixture';
  final jsonString = await File(fixturePath).readAsString();

  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);

  final uuidGen = SeededUuidGenerator(seed);
  final clock = FixedClock(
    DateTime.fromMillisecondsSinceEpoch(clockMs, isUtc: true),
  );

  // Route the parser's fall-back timestamps through the same fixed clock
  // SpMapper uses so the golden files are byte-stable across machine
  // timezones.
  final data = SpParser.parse(jsonString, now: clock.now);

  final syncHandle = RecordingSyncHandle();
  final progress = RecordingProgressSink();
  final errors = RecordingErrorReporter();
  final streamCounter = StreamUpdateCounter();

  syncHandle.install();
  errors.install();
  streamCounter.start(db);

  // The importer persists emissions into the durable outbox inside its
  // transaction (gated on persisted sync credentials) instead of replaying them
  // through the FFI sink post-commit. Flip the gate on for all fixtures so
  // parity is observed against the outbox rows — matching the prior harness,
  // which recorded the emission multiset regardless of pairing (the `unpaired`
  // distinction is the zero-error-report assertion, not a different emission
  // set).
  syncCredentialsPersisted.value = true;

  addTearDown(() async {
    syncHandle.remove();
    errors.remove();
    await streamCounter.stop();
    syncCredentialsPersisted.value = false;
    debugDisposeOutboxDrainForTesting();
  });

  // All repositories wired to the real Drift DB with null sync handle —
  // the capture sink intercepts the FFI dispatch regardless of handle.
  // For `unpaired`, the handle is null in production too, but the sink
  // captures (suppressed paths don't reach the sink — that's by design,
  // and the `failing_tx` fixture leans on it).
  //
  // For `failing_tx`, the harness wraps `memberRepo` so the first call to
  // `getAllMembers` inside the transaction throws — this rolls back every
  // queued batch insert before any DAO write commits. Phase 6 collapsed
  // most per-row repo calls into direct DAO batches, but the importer
  // still calls `memberRepo.getAllMembers()` once at the top of the
  // members loop (pre-resolve existence detection — review v1 feedback).
  // That single call is the harness's *early-failure* injection point —
  // a complementary *mid-batch* failure path lives in
  // `_runMidBatchFailureParity` below, which injects a throw in
  // `ChatMessagesDao.batchInsertMessages` after members + sessions have
  // already batched successfully.
  final memberRepoBase = DriftMemberRepository(db.membersDao, null);
  final MemberRepository memberRepo = failingTx
      ? _EarlyFailingMemberRepository(memberRepoBase)
      : memberRepoBase;
  final sessionRepo = DriftFrontingSessionRepository(
    db.frontingSessionsDao,
    null,
  );
  final conversationRepo = DriftConversationRepository(
    db.conversationsDao,
    null,
  );
  final messageRepo = DriftChatMessageRepository(db.chatMessagesDao, null);
  final pollRepo = DriftPollRepository(
    db.pollsDao,
    db.pollOptionsDao,
    db.pollVotesDao,
    null,
  );
  final notesRepo = DriftNotesRepository(db.notesDao, null);
  final commentsRepo = DriftFrontSessionCommentsRepository(
    db.frontSessionCommentsDao,
    null,
  );
  final customFieldsRepo = DriftCustomFieldsRepository(
    db.customFieldsDao,
    null,
  );
  final groupsRepo = DriftMemberGroupsRepository(
    db.memberGroupsDao,
    null,
    memberRepository: memberRepo,
  );
  final remindersRepo = DriftRemindersRepository(db.remindersDao, null);
  final categoriesRepo = DriftConversationCategoriesRepository(
    db.conversationCategoriesDao,
    null,
  );
  final settingsRepo = DriftSystemSettingsRepository(
    db.systemSettingsDao,
    null,
  );
  final boardPostsRepo = DriftMemberBoardPostsRepository(
    db.memberBoardPostsDao,
    db.membersDao,
    null,
  );

  // Failure-injection wiring lives above on `memberRepo`. Phase 6's batch
  // path bypasses `messageRepo.createMessage`, so wrapping the chat-message
  // repo is no longer load-bearing for the rollback assertion. See the
  // `_EarlyFailingMemberRepository` definition for the early-failure
  // injection point, and `_runMidBatchFailureParity` below for the
  // complementary mid-batch path.
  final importer = SpImporter(
    httpClient: _NoopHttpClient(),
    newId: uuidGen.next,
    now: clock.now,
  );

  Object? caught;
  try {
    await importer.executeImport(
      db: db,
      data: data,
      memberRepo: memberRepo,
      sessionRepo: sessionRepo,
      conversationRepo: conversationRepo,
      messageRepo: messageRepo,
      pollRepo: pollRepo,
      notesRepo: notesRepo,
      commentsRepo: commentsRepo,
      customFieldsRepo: customFieldsRepo,
      groupsRepo: groupsRepo,
      remindersRepo: remindersRepo,
      categoriesRepo: categoriesRepo,
      settingsRepo: settingsRepo,
      boardPostsRepo: boardPostsRepo,
      spImportDao: db.spImportDao,
      downloadAvatars: false,
      onProgress: progress.onProgress,
    );
  } catch (e) {
    caught = e;
  }

  if (failingTx) {
    expect(
      caught,
      isNotNull,
      reason: 'failing_tx fixture: import must propagate the exception',
    );
  } else {
    expect(caught, isNull, reason: 'fixture $fixture should import cleanly');
  }

  // Drain the stream-update notifications. Drift coalesces them with a
  // microtask delay; one extra flush makes the count stable.
  await Future<void>.delayed(const Duration(milliseconds: 50));

  // ---------- Observed outputs ----------
  final snapshot = await snapshotDb(db);
  // The importer now persists its in-transaction emissions into the
  // durable outbox (the drain trigger fires with a null handle in the harness,
  // so the rows are deferred, not dispatched — they sit in the table for
  // inspection). A rolled-back import leaves zero outbox rows, so the
  // failing_tx golden's emission array stays `[]` and assertion 2 converges
  // with assertion 4.
  //
  // A few emissions happen LIVE *after* the import transaction commits — the
  // post-import "auto-enable boards + nav overflow" settings writes. In
  // production those flow through the same outbox; in the harness the installed
  // capture sink short-circuits the live `syncRecord*` path before the outbox
  // enqueue, so they land in `syncHandle.recordings` instead. Merge both
  // sources so the observed multiset is the full production emission set. Order
  // is irrelevant — assertion 2 compares multisets.
  final outboxRows = await db.syncOutboxDao.allInIdOrder();
  final emissions = List<RecordedEmission>.unmodifiable([
    ...outboxRows.map(RecordedEmission.fromOutboxRow),
    ...syncHandle.recordings,
  ]);
  final progressEvents = List<ProgressEvent>.unmodifiable(progress.events);
  final errorReports = List<RecordedError>.unmodifiable(errors.errors);
  final streamUpdates = Map<String, int>.unmodifiable(
    streamCounter.totalByTable,
  );

  // ---------- Golden management ----------
  final goldenFile = File('$_goldenDir/$golden');
  final baseline = await _readOrWriteGolden(
    goldenFile: goldenFile,
    observed: _BaselineDump(
      snapshot: snapshot,
      emissions: emissions,
      progress: progressEvents,
      errorReports: errorReports,
      streamUpdates: streamUpdates,
    ),
  );

  // ---------- Assertions ----------

  // (1) DB snapshot byte-equal.
  expect(
    snapshot,
    baseline.snapshot,
    reason: '[assert 1/6] DB snapshot for $fixture must match baseline',
  );

  // (2) Emission multiset equal (set-equal regardless of order).
  //
  // Runs unconditionally — including for `failing_tx`. The Phase 5
  // post-commit replay drops the captured list when the transaction
  // throws, so the failing_tx golden's `emissions` array is `[]` and this
  // assertion converges with assertion 4 (below) for that fixture.
  expect(
    _multiset(emissions),
    _multiset(baseline.emissions),
    reason: '[assert 2/6] emission multiset for $fixture must match baseline',
  );

  // (3) Progress sequence equal.
  expect(
    progressEvents,
    baseline.progress,
    reason: '[assert 3/6] progress sequence for $fixture must match baseline',
  );

  // (4) failing_tx → zero emissions.
  //
  // Phase 5 of `docs/plans/sp-import-perf-quick-wins.md` is the load-bearing
  // fix for this assertion. The importer now wraps its transaction in
  // `SyncRecordMixin.suppressAndCapture` and replays captured tuples
  // *after* the transaction commits — so if the transaction throws, the
  // captured list is dropped in `suppressAndCapture`'s `finally` and the
  // replay loop never runs. The harness sink therefore sees zero
  // `RecordedEmission`s.
  if (failingTx) {
    expect(
      emissions,
      isEmpty,
      reason: '[assert 4/6] failing_tx: zero emissions when txn rolls back',
    );
  }

  // (5) unpaired → zero error reports.
  if (unpaired) {
    expect(
      errorReports,
      isEmpty,
      reason: '[assert 5/6] unpaired: zero ErrorReportingService reports',
    );
  }

  // (6) Stream updates per table ≥ baseline.
  for (final entry in baseline.streamUpdates.entries) {
    final actual = streamUpdates[entry.key] ?? 0;
    expect(
      actual,
      greaterThanOrEqualTo(entry.value),
      reason: '[assert 6/6] streamUpdates[${entry.key}] dropped below baseline',
    );
  }
}

// ---------------------------------------------------------------------------
// Golden file I/O
// ---------------------------------------------------------------------------

class _BaselineDump {
  _BaselineDump({
    required this.snapshot,
    required this.emissions,
    required this.progress,
    required this.errorReports,
    required this.streamUpdates,
  });

  final String snapshot;
  final List<RecordedEmission> emissions;
  final List<ProgressEvent> progress;
  final List<RecordedError> errorReports;
  final Map<String, int> streamUpdates;

  Map<String, Object?> toJson() => {
    'snapshot': snapshot,
    'emissions': emissions.map((e) => e.toJson()).toList(),
    'progress': progress.map((p) => p.toJson()).toList(),
    'errorReports': errorReports.map((e) => e.toJson()).toList(),
    'streamUpdates': streamUpdates,
  };

  static _BaselineDump fromJson(Map<String, Object?> json) {
    return _BaselineDump(
      snapshot: json['snapshot'] as String,
      emissions: (json['emissions'] as List)
          .cast<Map<String, Object?>>()
          .map(
            (m) => RecordedEmission(
              table: m['table'] as String,
              entityId: m['entity_id'] as String,
              opType: SyncRecordOpType.values.firstWhere(
                (t) => t.name == m['op_type'],
              ),
              fieldsJsonNormalized: m['fields'] as String,
            ),
          )
          .toList(),
      progress: (json['progress'] as List)
          .cast<Map<String, Object?>>()
          .map(
            (m) => ProgressEvent(
              current: m['current'] as int,
              total: m['total'] as int,
              label: m['label'] as String,
            ),
          )
          .toList(),
      errorReports: (json['errorReports'] as List)
          .cast<Map<String, Object?>>()
          .map(
            (m) => RecordedError(
              message: m['message'] as String,
              severity: ErrorSeverity.values.firstWhere(
                (s) => s.name == m['severity'],
              ),
            ),
          )
          .toList(),
      streamUpdates: ((json['streamUpdates'] as Map).cast<String, Object?>())
          .map((k, v) => MapEntry(k, v as int)),
    );
  }
}

Future<_BaselineDump> _readOrWriteGolden({
  required File goldenFile,
  required _BaselineDump observed,
}) async {
  if (_updateGoldens) {
    await goldenFile.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await goldenFile.writeAsString('${encoder.convert(observed.toJson())}\n');
    return observed;
  }
  if (!goldenFile.existsSync()) {
    fail(
      'Golden missing at ${goldenFile.path}; rerun with '
      'PRISM_UPDATE_PARITY_GOLDENS=1 to create it, or restore from git.',
    );
  }
  final raw = await goldenFile.readAsString();
  final decoded = jsonDecode(raw);
  return _BaselineDump.fromJson(decoded as Map<String, Object?>);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Multiset (counting-set) of recorded emissions. `_multiset(a) == _multiset(b)`
/// iff `a` and `b` are set-equal (order-blind).
Map<RecordedEmission, int> _multiset(Iterable<RecordedEmission> items) {
  final out = <RecordedEmission, int>{};
  for (final i in items) {
    out.update(i, (v) => v + 1, ifAbsent: () => 1);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Mid-batch failure driver (Phase 6 fix-up)
// ---------------------------------------------------------------------------

/// Drive the importer against a DB whose `chatMessagesDao.batchInsertMessages`
/// always throws. The throw fires after members + sessions have already
/// batched successfully, so this validates that:
///
///   1. The Drift transaction's atomicity rolls back ALL prior batch inserts
///      (members, fronting_sessions, etc.) — DB snapshot must show empty
///      tables after the throw.
///   2. `SyncRecordMixin.suppressAndCapture`'s `try`/`finally` guarantees
///      that the captured-emissions list goes out of scope without being
///      replayed — even though `captured.addAll(...)` ran for the
///      successful earlier batches inside the transaction.
///
/// This is the missing coverage review flagged in their review of 22354929:
/// the original `failing_tx` test throws BEFORE any insert, so it can't
/// distinguish "transaction never started writing" from "transaction wrote
/// + rolled back". This test forces the second case.
///
/// Assertion-only — no golden file. The contract is universal (empty
/// snapshot + empty emissions on mid-batch throw) and doesn't need a
/// per-fixture baseline.
Future<void> _runMidBatchFailureParity({
  required String fixture,
  required int seed,
  required int clockMs,
}) async {
  final fixturePath = '$_fixtureDir/$fixture';
  final jsonString = await File(fixturePath).readAsString();

  final db = _MidBatchFailingAppDatabase(NativeDatabase.memory());
  addTearDown(db.close);

  final uuidGen = SeededUuidGenerator(seed);
  final clock = FixedClock(
    DateTime.fromMillisecondsSinceEpoch(clockMs, isUtc: true),
  );

  final data = SpParser.parse(jsonString, now: clock.now);

  // Sanity: the fixture must include rows that batch BEFORE messages, so
  // the mid-batch throw actually exercises the "some batches committed,
  // later batch throws" path. Members + fronting sessions both batch
  // before messages (importer steps 1 and 4; messages is step 9).
  expect(
    data.members,
    isNotEmpty,
    reason:
        'fixture must include members so the early batch lands '
        'before the mid-batch throw',
  );
  expect(
    data.frontHistory,
    isNotEmpty,
    reason:
        'fixture must include front history so the second batch '
        'lands before the mid-batch throw',
  );
  expect(
    data.messages,
    isNotEmpty,
    reason:
        'fixture must include chat messages so '
        'batchInsertMessages is reached',
  );

  final syncHandle = RecordingSyncHandle();
  final progress = RecordingProgressSink();
  final errors = RecordingErrorReporter();

  syncHandle.install();
  errors.install();
  // Emissions are persisted into the outbox inside the import transaction;
  // a mid-batch rollback must roll BOTH the data and the outbox rows back.
  syncCredentialsPersisted.value = true;

  addTearDown(() {
    syncHandle.remove();
    errors.remove();
    syncCredentialsPersisted.value = false;
    debugDisposeOutboxDrainForTesting();
  });

  final memberRepo = DriftMemberRepository(db.membersDao, null);
  final sessionRepo = DriftFrontingSessionRepository(
    db.frontingSessionsDao,
    null,
  );
  final conversationRepo = DriftConversationRepository(
    db.conversationsDao,
    null,
  );
  final messageRepo = DriftChatMessageRepository(db.chatMessagesDao, null);
  final pollRepo = DriftPollRepository(
    db.pollsDao,
    db.pollOptionsDao,
    db.pollVotesDao,
    null,
  );
  final notesRepo = DriftNotesRepository(db.notesDao, null);
  final commentsRepo = DriftFrontSessionCommentsRepository(
    db.frontSessionCommentsDao,
    null,
  );
  final customFieldsRepo = DriftCustomFieldsRepository(
    db.customFieldsDao,
    null,
  );
  final groupsRepo = DriftMemberGroupsRepository(
    db.memberGroupsDao,
    null,
    memberRepository: memberRepo,
  );
  final remindersRepo = DriftRemindersRepository(db.remindersDao, null);
  final categoriesRepo = DriftConversationCategoriesRepository(
    db.conversationCategoriesDao,
    null,
  );
  final settingsRepo = DriftSystemSettingsRepository(
    db.systemSettingsDao,
    null,
  );
  final boardPostsRepo = DriftMemberBoardPostsRepository(
    db.memberBoardPostsDao,
    db.membersDao,
    null,
  );

  final importer = SpImporter(
    httpClient: _NoopHttpClient(),
    newId: uuidGen.next,
    now: clock.now,
  );

  Object? caught;
  try {
    await importer.executeImport(
      db: db,
      data: data,
      memberRepo: memberRepo,
      sessionRepo: sessionRepo,
      conversationRepo: conversationRepo,
      messageRepo: messageRepo,
      pollRepo: pollRepo,
      notesRepo: notesRepo,
      commentsRepo: commentsRepo,
      customFieldsRepo: customFieldsRepo,
      groupsRepo: groupsRepo,
      remindersRepo: remindersRepo,
      categoriesRepo: categoriesRepo,
      settingsRepo: settingsRepo,
      boardPostsRepo: boardPostsRepo,
      spImportDao: db.spImportDao,
      downloadAvatars: false,
      onProgress: progress.onProgress,
    );
  } catch (e) {
    caught = e;
  }

  // Drain pending stream-update microtasks so the test doesn't race a
  // late notification into the next test's setUp.
  await Future<void>.delayed(const Duration(milliseconds: 50));

  // The mid-batch throw MUST propagate out of the importer.
  expect(
    caught,
    isNotNull,
    reason: 'mid-batch failure: import must propagate the exception',
  );
  expect(
    db.failingDao.threwOnBatchInsert,
    isTrue,
    reason:
        'mid-batch failure: batchInsertMessages must have been '
        'reached (proves members + sessions batched first)',
  );

  // Assertion A: snapshot empty — transaction rolled back every
  // earlier batch (members, sessions) along with the failed messages
  // batch.
  final snapshot = await snapshotDb(db);
  final decoded = jsonDecode(snapshot) as Map<String, Object?>;
  final tables = (decoded['tables'] as Map).cast<String, Object?>();
  for (final entry in tables.entries) {
    final rows = entry.value as List;
    expect(
      rows,
      isEmpty,
      reason:
          'mid-batch failure: table ${entry.key} must be empty '
          'after rollback (had ${rows.length} rows; transaction '
          'atomicity broken)',
    );
  }

  // Assertion B: emissions empty — the importer persists captured ops into the outbox
  // inside the transaction, so a mid-batch rollback discards them atomically
  // with the data rows. Zero outbox rows == zero emissions reached any peer.
  expect(
    await db.syncOutboxDao.allInIdOrder(),
    isEmpty,
    reason:
        'mid-batch failure: outbox rows must roll back with the data '
        '(no emission can survive an uncommitted import)',
  );
}

class _NoopHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Avatar download is disabled in the harness (`downloadAvatars: false`),
    // but any stray HTTP request still needs a response.
    return http.StreamedResponse(const Stream.empty(), 404);
  }
}

/// Wraps a real `MemberRepository` and throws on the first `getAllMembers`
/// call — BEFORE any insert runs. Used to force a transaction rollback in
/// the `failing_tx` fixture's early-failure path.
///
/// Phase 6's batch path bypasses every per-row `*.create*()` repository
/// call, so the pre-Phase-6 throwing wrapper that intercepted
/// `messageRepo.createMessage` no longer fires. The SP importer still
/// calls `memberRepo.getAllMembers()` once at the top of its members loop
/// (pre-resolve existing-member detection), so that's the durable
/// early-failure injection point that survives every later batching pass.
///
/// For the complementary mid-batch failure path (throw AFTER at least one
/// successful batch insert), see `_MidBatchFailingChatMessagesDao` /
/// `_MidBatchFailingAppDatabase` further down.
class _EarlyFailingMemberRepository implements MemberRepository {
  
  Future<void> stampCreatePushStartedAt(String id, int timestampMs) async {}
  
  Future<void> clearCreatePushStartedAt(String id) async {}
  _EarlyFailingMemberRepository(this._inner);
  final MemberRepository _inner;
  bool _thrown = false;

  @override
  Future<List<member_domain.Member>> getAllMembers() async {
    if (!_thrown) {
      _thrown = true;
      throw Exception('parity harness: forced rollback');
    }
    return _inner.getAllMembers();
  }

  @override
  Future<void> clearPluralKitLink(String id) => _inner.clearPluralKitLink(id);

  @override
  Future<void> createMember(member_domain.Member member) =>
      _inner.createMember(member);

  @override
  Future<void> deleteMember(String id) => _inner.deleteMember(id);

  @override
  Future<List<member_domain.Member>> getAllMembersIncludingDeleted() =>
      _inner.getAllMembersIncludingDeleted();

  @override
  Future<int> getCount() => _inner.getCount();

  @override
  Future<List<member_domain.Member>> getDeletedLinkedMembers() =>
      _inner.getDeletedLinkedMembers();

  @override
  Future<member_domain.Member?> getMemberById(String id) =>
      _inner.getMemberById(id);

  @override
  Future<List<member_domain.Member>> getMembersByIds(List<String> ids) =>
      _inner.getMembersByIds(ids);

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) =>
      _inner.stampDeletePushStartedAt(id, timestampMs);

  @override
  Future<void> updateMember(member_domain.Member member) =>
      _inner.updateMember(member);

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) => _inner.updateMemberFields(id, changedFields);

  @override
  Future<int> applyPluralKitLink(String id, Map<String, dynamic> patch) =>
      _inner.applyPluralKitLink(id, patch);

  @override
  Future<int> recordPluralKitIdentity(String id, Map<String, dynamic> patch) =>
      _inner.recordPluralKitIdentity(id, patch);

  @override
  Future<int> excludePluralKitSync(String id) => _inner.excludePluralKitSync(id);

  @override
  Future<int> resumePluralKitSync(String id) => _inner.resumePluralKitSync(id);

  @override
  Stream<List<member_domain.Member>> watchActiveMembers() =>
      _inner.watchActiveMembers();

  @override
  Stream<List<member_domain.Member>> watchAllMembers() =>
      _inner.watchAllMembers();

  @override
  Stream<member_domain.Member?> watchMemberById(String id) =>
      _inner.watchMemberById(id);

  @override
  Stream<List<member_domain.Member>> watchMembersByIds(List<String> ids) =>
      _inner.watchMembersByIds(ids);

  @override
  Future<({member_domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => _inner.ensureUnknownSentinelMember();
}

/// Subclass of `ChatMessagesDao` that throws on `batchInsertMessages` —
/// the mid-batch failure injection point for the Phase 6 fix-up coverage.
///
/// Every other DAO operation passes through to the parent (real Drift)
/// implementation. The throw fires the first time `batchInsertMessages`
/// is called with a non-empty list (the importer guards the call with
/// `if (messageCompanions.isNotEmpty)`, so a no-op call would not test
/// anything meaningful).
class _MidBatchFailingChatMessagesDao extends ChatMessagesDao {
  _MidBatchFailingChatMessagesDao(super.db);

  bool threwOnBatchInsert = false;

  @override
  Future<void> batchInsertMessages(List<ChatMessagesCompanion> rows) async {
    if (rows.isEmpty) {
      // Pass through no-op calls so we only mark the throw flag when the
      // importer actually had messages to insert.
      return super.batchInsertMessages(rows);
    }
    threwOnBatchInsert = true;
    throw Exception(
      'parity harness: forced mid-batch rollback in batchInsertMessages',
    );
  }
}

/// Subclass of `AppDatabase` that swaps the real `chatMessagesDao` getter
/// for a `_MidBatchFailingChatMessagesDao`. Everything else (other DAOs,
/// transactions, schema, migration) inherits the real implementation.
///
/// The failing DAO is `late final` so every call to `db.chatMessagesDao`
/// returns the same instance — the importer's reference and the test's
/// post-mortem inspection (`db.failingDao.threwOnBatchInsert`) see the
/// same object.
class _MidBatchFailingAppDatabase extends AppDatabase {
  _MidBatchFailingAppDatabase(super.e);

  late final _MidBatchFailingChatMessagesDao failingDao =
      _MidBatchFailingChatMessagesDao(this);

  @override
  ChatMessagesDao get chatMessagesDao => failingDao;
}
