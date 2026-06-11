/// Live PluralKit integration test for stale member-link recovery.
///
/// Excluded from CI. Run manually with a dedicated PluralKit test token:
///
///   PK_TEST_TOKEN=your-token flutter test --tags integration \
///     test/features/pluralkit/services/pk_live_stale_link_recovery_integration_test.dart
///
/// Safety:
///   * If PK_TEST_TOKEN and PK_TOKEN are unset, the test is skipped.
///   * The test creates one temporary PK member with [_kPrefix].
///   * Cleanup deletes the tracked member ID and sweeps the prefix.
@Tags(['integration'])
library;

import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
// Use the pure Dart test package so Flutter's widget-test HTTP override does
// not intercept live PluralKit requests.
// ignore: depend_on_referenced_packages
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

String? get _tokenOrNull {
  final testToken = Platform.environment['PK_TEST_TOKEN']?.trim();
  if (testToken != null && testToken.isNotEmpty) return testToken;
  final token = Platform.environment['PK_TOKEN']?.trim();
  if (token != null && token.isNotEmpty) return token;
  return null;
}

const _skipReason =
    'Set PK_TEST_TOKEN or PK_TOKEN to run the live PluralKit stale-link test.';

final String _kPrefix = _buildPrefix();

String _buildPrefix() {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final rand = Random.secure().nextInt(0x7fffffff).toRadixString(36);
  return 'prism-stale-link-it-$ts-$rand-';
}

void main() {
  final token = _tokenOrNull;

  group(
    'live PK stale-link recovery',
    skip: token == null ? _skipReason : false,
    () {
      test(
        'pushMemberUpdate returns false and clears the local link after live 404',
        () async {
          final setupHttpClient = http.Client();
          final setupClient = PluralKitClient(
            token: token!,
            httpClient: setupHttpClient,
            bus: PkSyncEventBus(),
          );
          final createdMemberIds = <String>{};

          try {
            final runId = const Uuid().v4().split('-').first;
            final pkMember = await setupClient.createMember({
              'name': '$_kPrefix$runId-member',
              'display_name': 'Prism stale link $runId',
            });
            createdMemberIds.add(pkMember.id);

            final db = AppDatabase(NativeDatabase.memory());
            addTearDown(db.close);

            final memberRepo = DriftMemberRepository(db.membersDao, null);
            final sessionRepo = DriftFrontingSessionRepository(
              db.frontingSessionsDao,
              null,
              pkSyncDao: db.pluralKitSyncDao,
            );

            final local = domain.Member(
              id: 'local-$runId',
              name: 'Prism stale link $runId',
              createdAt: DateTime.now().toUtc(),
              pluralkitId: pkMember.id,
              pluralkitUuid: pkMember.uuid,
              pluralkitDisplayName: pkMember.displayName,
            );
            await memberRepo.createMember(local);

            await setupClient.deleteMember(pkMember.id);

            late _RecordingPluralKitClient serviceClient;
            final service = PluralKitSyncService(
              memberRepository: memberRepo,
              frontingSessionRepository: sessionRepo,
              syncDao: db.pluralKitSyncDao,
              bus: PkSyncEventBus(),
              tokenOverride: token,
              clientFactory: (resolvedToken) {
                serviceClient = _RecordingPluralKitClient(token: resolvedToken);
                return serviceClient;
              },
            );
            await _seedPostWizardState(service, db);

            final result = await service.pushMemberUpdate(
              local.copyWith(pronouns: 'stale-link-$runId'),
            );

            expect(result, isFalse);
            expect(
              serviceClient.sawMemberUpdate404,
              isTrue,
              reason:
                  'The production push path should encounter PK member 404.',
            );
            expect(
              service.state.syncError,
              isNull,
              reason:
                  'pushMemberUpdate swallows stale-link failures for edits.',
            );

            final reloaded = await memberRepo.getMemberById(local.id);
            expect(reloaded, isNotNull);
            expect(reloaded!.pluralkitId, isNull);
            expect(reloaded.pluralkitUuid, isNull);
            expect(reloaded.pluralkitSyncIgnored, isFalse);
          } finally {
            for (final memberId in createdMemberIds.toList()) {
              try {
                await setupClient.deleteMember(memberId);
              } catch (_) {
                // Best-effort cleanup. The main test deletes this member first.
              }
            }

            try {
              final allMembers = await setupClient.getMembers();
              for (final member in allMembers) {
                if (member.name.startsWith(_kPrefix)) {
                  try {
                    await setupClient.deleteMember(member.id);
                  } catch (_) {
                    // Best-effort cleanup.
                  }
                }
              }
            } catch (_) {
              // Best-effort cleanup.
            }

            setupClient.dispose();
            setupHttpClient.close();
          }
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
  );
}

Future<void> _seedPostWizardState(
  PluralKitSyncService service,
  AppDatabase db,
) async {
  final now = DateTime.now().toUtc();
  await db.pluralKitSyncDao.upsertSyncState(
    PluralKitSyncStateCompanion(
      id: const Value('pk_config'),
      isConnected: const Value(true),
      systemId: const Value('live-stale-link-test'),
      directionConfirmed: const Value(true),
      mappingAcknowledged: const Value(true),
      linkedAt: Value(now.subtract(const Duration(minutes: 1))),
      // 2026-06 PK audit M11: pushMemberUpdate now gates the payload by the
      // configured direction (pull-only default = no push). Seed the
      // push-enabled direction a production edit-push user actually has.
      fieldSyncConfig: Value(
        serializeFieldSyncConfigWithGlobalDirection(
          null,
          PkSyncDirection.bidirectional,
        ),
      ),
    ),
  );
  await service.loadState();
}

class _RecordingPluralKitClient extends PluralKitClient {
  _RecordingPluralKitClient({required super.token})
    : super(httpClient: http.Client(), bus: PkSyncEventBus());

  var sawMemberUpdate404 = false;

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) async {
    try {
      return await super.updateMember(id, data);
    } on PluralKitApiError catch (error) {
      if (error.statusCode == 404) {
        sawMemberUpdate404 = true;
      }
      rethrow;
    }
  }
}
