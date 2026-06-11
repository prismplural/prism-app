/// Live PluralKit repro harness for same-timestamp zero-duration switches.
///
/// Excluded from CI. Run manually with a dedicated test account:
///
///   PK_TEST_TOKEN=your-token flutter test --tags integration \
///     test/features/pluralkit/services/pk_live_zero_length_repro_test.dart
///
/// The harness creates two temporary PluralKit members, tries to create two
/// switches with the exact same timestamp (B enters, then nobody fronts),
/// imports that payload shape through Prism, asserts B is not left as a phantom
/// open row, and cleans up the remote switches/members. Current PK rejects
/// exact duplicate timestamps through the write API, so the harness falls back
/// to a live-created switch with a synthetic same-timestamp import payload.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
// Use the pure Dart test package so Flutter's widget-test HTTP override does
// not intercept live PluralKit requests.
// ignore: depend_on_referenced_packages
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

void main() {
  final token = Platform.environment['PK_TEST_TOKEN']?.trim().isNotEmpty == true
      ? Platform.environment['PK_TEST_TOKEN']!.trim()
      : Platform.environment['PK_TOKEN']?.trim();
  final hasToken = token != null && token.isNotEmpty;

  group(
    'live PK zero-length switch repro',
    skip: hasToken
        ? false
        : 'Set PK_TEST_TOKEN or PK_TOKEN to run the live PluralKit harness.',
    () {
      test(
        'same-timestamp transient live switch does not produce phantom row',
        () async {
          final liveClient = PluralKitClient(
            token: token!,
            httpClient: http.Client(),
            bus: PkSyncEventBus(),
          );
          final createdSwitchIds = <String>[];
          final createdMemberIds = <String>[];

          try {
            final runId = const Uuid().v4().split('-').first;
            final timestamp = DateTime.now().toUtc().subtract(
              const Duration(days: 180),
            );

            final memberA = await liveClient.createMember({
              'name': 'prism-repro-a-$runId',
            });
            final memberB = await liveClient.createMember({
              'name': 'prism-repro-b-$runId',
            });
            createdMemberIds.addAll([memberA.id, memberB.id]);

            final enterB = await liveClient.createSwitch([
              memberB.id,
            ], timestamp: timestamp);
            createdSwitchIds.add(enterB.id);

            late final PKSwitch leaveBForImport;
            try {
              final liveDuplicateLeave = await liveClient.createSwitch(
                const [],
                timestamp: timestamp,
              );
              createdSwitchIds.add(liveDuplicateLeave.id);
              leaveBForImport = liveDuplicateLeave;
            } on PluralKitApiError catch (error) {
              if (!error.message.contains('timestamp already exists')) {
                rethrow;
              }
              final liveFallbackLeave = await liveClient.createSwitch(
                const [],
                timestamp: timestamp.add(const Duration(seconds: 1)),
              );
              createdSwitchIds.add(liveFallbackLeave.id);
              leaveBForImport = PKSwitch(
                id: _lexicallyAfter(enterB.id),
                timestamp: enterB.timestamp,
                members: liveFallbackLeave.members,
                memberDetails: liveFallbackLeave.memberDetails,
              );
            }

            expect(
              leaveBForImport.timestamp.toUtc().microsecondsSinceEpoch,
              enterB.timestamp.toUtc().microsecondsSinceEpoch,
              reason:
                  'The Prism import payload must exercise same-time switches.',
            );
            expect(
              leaveBForImport.id.compareTo(enterB.id),
              greaterThan(0),
              reason:
                  'The leaving switch must sort after the entering switch under '
                  'Prism/PK cursor ordering.',
            );

            final db = AppDatabase(NativeDatabase.memory());
            addTearDown(db.close);

            final memberRepo = DriftMemberRepository(db.membersDao, null);
            await memberRepo.createMember(
              _localMember(
                id: 'local-a-$runId',
                pkMember: memberA,
                displayOrder: 0,
              ),
            );
            await memberRepo.createMember(
              _localMember(
                id: 'local-b-$runId',
                pkMember: memberB,
                displayOrder: 1,
              ),
            );

            final sessionRepo = DriftFrontingSessionRepository(
              db.frontingSessionsDao,
              null,
            );
            await db.pluralKitSyncDao.upsertSyncState(
              const PluralKitSyncStateCompanion(
                id: Value('pk_config'),
                isConnected: Value(true),
                directionConfirmed: Value(true),
                mappingAcknowledged: Value(true),
              ),
            );

            final scopedClient = _ScopedSwitchClient(
              delegate: liveClient,
              switchesNewestFirst: [leaveBForImport, enterB],
            );
            final service = PluralKitSyncService(
              memberRepository: memberRepo,
              frontingSessionRepository: sessionRepo,
              syncDao: db.pluralKitSyncDao,
              bus: PkSyncEventBus(),
              clientFactory: (_) => scopedClient,
              tokenOverride: 'pk-live-repro-token-override',
            );

            await service.loadState();
            await service.importSwitchesAfterLink();

            final sessions = await sessionRepo.getAllSessions();
            expect(
              sessions.where((s) => s.memberId == 'local-b-$runId'),
              isEmpty,
              reason:
                  'The temporary B member only fronted for a zero-duration '
                  'same-timestamp interval and must not survive as a Prism row.',
            );
            final bRow = await sessionRepo.getSessionById(
              derivePkSessionId(enterB.id, memberB.uuid),
            );
            expect(bRow?.isDeleted, isTrue);
            expect(bRow?.pluralkitUuid, isNull);
            expect(await sessionRepo.getDeletedLinkedSessions(), isEmpty);
          } finally {
            for (final switchId in createdSwitchIds.reversed) {
              try {
                await liveClient.deleteSwitch(switchId);
              } catch (_) {
                // Best-effort cleanup; keep going so later artifacts are removed.
              }
            }
            for (final memberId in createdMemberIds.reversed) {
              try {
                await liveClient.deleteMember(memberId);
              } catch (_) {
                // Best-effort cleanup.
              }
            }
            liveClient.dispose();
          }
        },
      );
    },
  );
}

String _lexicallyAfter(String value) => '$value~zero-length-leave';

domain.Member _localMember({
  required String id,
  required PKMember pkMember,
  required int displayOrder,
}) {
  return domain.Member(
    id: id,
    name: pkMember.name,
    emoji: '?',
    createdAt: DateTime.now(),
    displayOrder: displayOrder,
    pluralkitId: pkMember.id,
    pluralkitUuid: pkMember.uuid,
  );
}

class _ScopedSwitchClient implements PluralKitClient {
  @override
  Future<PKSwitch> getSwitch(String switchRef) =>
      throw UnimplementedError();
  _ScopedSwitchClient({
    required this.delegate,
    required List<PKSwitch> switchesNewestFirst,
  }) : _switchesNewestFirst = List<PKSwitch>.of(switchesNewestFirst);

  final PluralKitClient delegate;
  final List<PKSwitch> _switchesNewestFirst;
  var _switchesReturned = false;

  @override
  String get currentToken => delegate.currentToken;

  @override
  Future<PKSystem> getSystem() => delegate.getSystem();

  @override
  Future<List<PKMember>> getMembers() => delegate.getMembers();

  @override
  Future<PKMember> getMember(String memberRef) => delegate.getMember(memberRef);

  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
    if (_switchesReturned) return const <PKSwitch>[];
    _switchesReturned = true;
    return List<PKSwitch>.of(_switchesNewestFirst);
  }

  @override
  Future<PKSwitch?> getCurrentFronters() => delegate.getCurrentFronters();

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async =>
      const <PKGroup>[];

  @override
  Future<List<String>> getGroupMembers(String groupRef) =>
      delegate.getGroupMembers(groupRef);

  @override
  Future<void> addMembersToGroup(String groupRef, List<String> memberRefs) =>
      delegate.addMembersToGroup(groupRef, memberRefs);

  @override
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> memberRefs,
  ) => delegate.removeMembersFromGroup(groupRef, memberRefs);

  @override
  Future<List<int>> downloadBytes(String url) => delegate.downloadBytes(url);

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      delegate.createMember(data);

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
      delegate.updateMember(id, data);

  @override
  Future<void> deleteMember(String id) => delegate.deleteMember(id);

  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) => delegate.createSwitch(memberIds, timestamp: timestamp);

  @override
  Future<PKSwitch> updateSwitch(
    String switchId, {
    required DateTime timestamp,
  }) => delegate.updateSwitch(switchId, timestamp: timestamp);

  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) => delegate.updateSwitchMembers(switchId, memberIds);

  @override
  Future<void> deleteSwitch(String switchId) => delegate.deleteSwitch(switchId);

  @override
  void dispose() {
    // The harness owns [delegate] and disposes it after remote cleanup.
  }
}
