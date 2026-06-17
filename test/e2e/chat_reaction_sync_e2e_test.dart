import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/message_reaction.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });
  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  test(
    'chat reaction updates sync in both directions',
    skip: e2eSkip(),
    () async {
      final relay = await spawnRelay();
      E2EDevice? phone;
      E2EDevice? windows;
      database.AppDatabase? phoneDb;
      try {
        phone = await createDevice(relay);
        windows = await pairNewDevice(relay, phone);
        phoneDb = database.AppDatabase(NativeDatabase.memory());
        final phoneSyncAdapter = buildSyncAdapterWithCompletion(phoneDb);
        final phoneQuarantine = SyncQuarantineService(
          phoneDb.syncQuarantineDao,
        );

        await ffi.recordCreate(
          handle: phone.handle,
          table: 'chat_messages',
          entityId: 'message-1',
          fieldsJson: jsonEncode(_messageFields(reactions: const [])),
        );
        expect((await phone.sync())['error'], isNull);
        expect((await windows.sync())['merged'], greaterThanOrEqualTo(1));
        await _applyToDb(
          phoneDb,
          _messageFields(
            reactions: [
              _reaction('phone-reaction', 'thumbs_up', 'phone-member'),
            ],
          ),
        );

        await ffi.recordUpdate(
          handle: phone.handle,
          table: 'chat_messages',
          entityId: 'message-1',
          changedFieldsJson: jsonEncode({
            'reactions': jsonEncode([
              _reaction('phone-reaction', 'thumbs_up', 'phone-member'),
            ]),
          }),
        );
        expect((await phone.sync())['error'], isNull);
        expect((await windows.sync())['error'], isNull);
        expect(
          await _reactionIds(windows.handle),
          ['phone-reaction'],
          reason: 'phone -> windows reaction update should apply',
        );

        await ffi.recordUpdate(
          handle: windows.handle,
          table: 'chat_messages',
          entityId: 'message-1',
          changedFieldsJson: jsonEncode({
            'reactions': jsonEncode([
              _reaction('phone-reaction', 'thumbs_up', 'phone-member'),
              _reaction('windows-reaction', 'heart', 'windows-member'),
            ]),
          }),
        );
        expect((await windows.sync())['error'], isNull);
        expect((await phone.sync())['error'], isNull);
        expect(
          await _reactionIds(phone.handle),
          ['phone-reaction', 'windows-reaction'],
          reason: 'windows -> phone reaction update should apply',
        );

        final drain = await drainRemoteDeliveries(
          phone.handle,
          db: phoneDb,
          syncAdapter: phoneSyncAdapter,
          quarantine: phoneQuarantine,
        );
        expect(drain.rowsApplied, greaterThanOrEqualTo(1));
        final phoneRow = await (phoneDb.select(
          phoneDb.chatMessages,
        )..where((t) => t.id.equals('message-1'))).getSingle();
        final phoneDbReactions =
            jsonDecode(phoneRow.reactions) as List<dynamic>;
        expect(
          phoneDbReactions
              .map(
                (reaction) =>
                    (reaction as Map<String, dynamic>)['id'] as String,
              )
              .toList(),
          ['phone-reaction', 'windows-reaction'],
          reason: 'windows -> phone remote delivery should patch Drift',
        );
      } finally {
        await phoneDb?.close();
        phone?.dispose();
        windows?.dispose();
        relay.stop();
      }
    },
  );

  test(
    'manual sync drains queued app reactions before pushing',
    skip: e2eSkip(),
    () async {
      final relay = await spawnRelay();
      E2EDevice? phone;
      E2EDevice? windows;
      database.AppDatabase? windowsDb;
      final previousCredentialsPersisted = syncCredentialsPersisted.value;
      final previousCurrentHandle = syncCurrentHandle.value;
      try {
        phone = await createDevice(relay);
        windows = await pairNewDevice(relay, phone);
        windowsDb = database.AppDatabase(NativeDatabase.memory());
        await _applyToDb(windowsDb, _messageFields(reactions: const []));

        syncCredentialsPersisted.value = true;
        syncCurrentHandle.value = windows.handle;
        SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
          db: windowsDb,
          drainTrigger: (_) async {},
        );

        await ffi.recordCreate(
          handle: phone.handle,
          table: 'chat_messages',
          entityId: 'message-1',
          fieldsJson: jsonEncode(_messageFields(reactions: const [])),
        );
        expect((await phone.sync())['error'], isNull);
        expect((await windows.sync())['merged'], greaterThanOrEqualTo(1));

        final repo = DriftChatMessageRepository(
          windowsDb.chatMessagesDao,
          windows.handle,
        );
        final message = await repo.getMessageById('message-1');
        expect(message, isNotNull);
        await repo.updateMessage(
          message!.copyWith(
            reactions: [
              MessageReaction(
                id: 'windows-reaction',
                emoji: 'heart',
                memberId: 'windows-member',
                timestamp: DateTime.utc(2026, 6, 15),
              ),
            ],
          ),
        );
        expect(await windowsDb.syncOutboxDao.count(), 1);

        await ffi.syncNow(handle: windows.handle);
        await phone.sync();
        expect(
          await _reactionIds(phone.handle),
          isEmpty,
          reason: 'raw sync_now raced ahead of the app outbox',
        );

        await syncNowAfterOutboxDrain(db: windowsDb, handle: windows.handle);
        await phone.sync();
        expect(
          await _reactionIds(phone.handle),
          ['windows-reaction'],
          reason: 'manual sync helper must flush the app outbox before push',
        );
      } finally {
        SyncRecordMixin.debugInstallOutboxRuntimeForTesting();
        debugDisposeOutboxDrainForTesting();
        syncCredentialsPersisted.value = previousCredentialsPersisted;
        syncCurrentHandle.value = previousCurrentHandle;
        await windowsDb?.close();
        phone?.dispose();
        windows?.dispose();
        relay.stop();
      }
    },
  );
}

Future<void> _applyToDb(
  database.AppDatabase db,
  Map<String, dynamic> fields,
) async {
  final adapter = buildSyncAdapterWithCompletion(db).adapter;
  final messages = adapter.entities.singleWhere(
    (entity) => entity.tableName == 'chat_messages',
  );
  await messages.applyFields('message-1', fields);
}

Map<String, dynamic> _messageFields({
  required List<Map<String, dynamic>> reactions,
}) {
  return {
    'content': 'hello',
    'timestamp': '2026-06-15T00:00:00.000Z',
    'is_system_message': false,
    'edited_at': null,
    'author_id': 'phone-member',
    'conversation_id': 'conversation-1',
    'reactions': jsonEncode(reactions),
    'reply_to_id': null,
    'reply_to_author_id': null,
    'reply_to_content': null,
    'is_deleted': false,
  };
}

Map<String, dynamic> _reaction(String id, String emoji, String memberId) {
  return {
    'id': id,
    'emoji': emoji,
    'memberId': memberId,
    'timestamp': '2026-06-15T00:00:00.000Z',
  };
}

Future<List<String>> _reactionIds(ffi.PrismSyncHandle handle) async {
  final raw = await ffi.readFieldValue(
    handle: handle,
    table: 'chat_messages',
    entityId: 'message-1',
    field: 'reactions',
  );
  expect(raw, isNotNull, reason: 'message reactions field exists');
  final reactionsJson = jsonDecode(raw!) as String;
  final reactions = jsonDecode(reactionsJson) as List<dynamic>;
  return reactions
      .map((reaction) => (reaction as Map<String, dynamic>)['id'] as String)
      .toList();
}
