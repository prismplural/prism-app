import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/features/data_management/models/export_models.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';

import 'pluralport_bundle.dart';
import 'pluralport_exporter.dart';
import 'pluralport_mapper.dart';
import 'pluralport_preservation.dart';

class PluralPortService {
  PluralPortService({
    required this.db,
    required this.exporter,
    required this.importer,
    MediaEncryptionService? encryption,
    Future<Directory> Function()? supportDirectory,
  }) : encryption = encryption ?? MediaEncryptionService(),
       supportDirectory = supportDirectory ?? getApplicationSupportDirectory;
  final AppDatabase db;
  final DataExportService exporter;
  final DataImportService importer;
  final MediaEncryptionService encryption;
  final Future<Directory> Function() supportDirectory;

  static PluralPortImportPlan previewBytes(Uint8List bytes) =>
      PluralPortMapper.plan(PluralPortBundle.decode(bytes));
  Future<PluralPortImportPlan> preview(Uint8List bytes) =>
      compute(previewBytes, bytes);

  Future<ImportResult> importPlan(
    PluralPortImportPlan plan, {
    bool importSystemProfile = false,
  }) async {
    final existingNative = (await exporter.buildExport()).toJson();
    final existingIds = <String>{
      for (final key in PluralPortMapper.collections.values)
        for (final row in PluralPortMapper.rows(existingNative, key))
          '$key/${row['id']}',
    };
    final desired = V1Export.fromJson(plan.native).toJson();
    final desiredRows = <String, Json>{
      for (final key in PluralPortMapper.collections.values)
        for (final row in PluralPortMapper.rows(desired, key))
          '$key/${row['id']}': row,
    };
    final data = PluralPortMapper.clone(plan.native);
    final archive = PluralPortMapper.clone(plan.archive);
    final previousProfiles =
        (existingNative['pluralPortArchives'] as List? ?? [])
            .whereType<Map>()
            .where(
              (a) =>
                  a['kind'] == 'import' &&
                  a['namespace'] == archive['namespace'] &&
                  a['systemProfileImported'] == true,
            )
            .toList()
          ..sort(
            (a, b) => (a['imported_at'] as String? ?? '').compareTo(
              b['imported_at'] as String? ?? '',
            ),
          );
    if (!importSystemProfile && previousProfiles.isNotEmpty) {
      archive['systemProfileImported'] = true;
      archive['systemBaseline'] = previousProfiles.last['systemBaseline'];
    }
    final envelope = archive['envelope'] as Json;
    final files = archive['files'] as Json;
    final assets = {
      for (final a in PluralPortMapper.rows(envelope, 'assets')) a['id']: a,
    };
    if (importSystemProfile) {
      final system = PluralPortMapper.rows(envelope, 'systems').firstOrNull;
      if (system != null) {
        final current =
            (await exporter.buildExport()).systemSettings.firstOrNull
                ?.toJson() ??
            {};
        data['systemSettings'] = [
          {
            ...current,
            'systemName': system['name'],
            'systemDescription': system['description'],
            'systemTag': system['tag'],
            'systemColor': system['color'],
            'systemAvatarData':
                files[assets[system['avatar_asset_id']]?['bundle_path']],
          },
        ];
        archive['systemProfileImported'] = true;
      }
    }
    // Only write values/messages whose parent was mapped to an app record.
    // Their source records stay archived when Prism cannot represent the parent.
    final fields = PluralPortMapper.rows(
      data,
      'customFields',
    ).map((r) => r['id']).toSet();
    final conversations = PluralPortMapper.rows(
      data,
      'conversations',
    ).map((r) => r['id']).toSet();
    data['customFieldValues'] = PluralPortMapper.rows(
      data,
      'customFieldValues',
    ).where((r) => fields.contains(r['customFieldId'])).toList();
    data['messages'] = PluralPortMapper.rows(
      data,
      'messages',
    ).where((r) => conversations.contains(r['conversationId'])).toList();
    final blobs = <({String mediaId, Uint8List blob})>[];
    final attachments = <Json>[];
    final mediaBindings = <String, String>{};
    final messages = PluralPortMapper.rows(
      data,
      'messages',
    ).map((r) => r['id']).toSet();
    for (final message in PluralPortMapper.rows(envelope, 'chat.messages')) {
      if (!messages.contains(message['id'])) continue;
      final assetIds = <dynamic>{
        ...message['attachment_asset_ids'] as List? ?? [],
        for (final attachment in PluralPortMapper.rows(
          envelope,
          'chat.attachments',
        ))
          if (attachment['message_id'] == message['id']) attachment['asset_id'],
      };
      for (final assetId in assetIds) {
        final asset = assets[assetId];
        final bytes = files[asset?['bundle_path']];
        if (bytes is! String || !['image', 'audio'].contains(asset?['kind'])) {
          continue;
        }
        final attachmentId = PluralPortMapper.stableId(
          message['id'] as String,
          assetId as String,
        );
        mediaBindings['${message['id']}/$assetId'] = attachmentId;
        final existing = await (db.select(
          db.mediaAttachments,
        )..where((t) => t.id.equals(attachmentId))).getSingleOrNull();
        if (existing != null) continue;
        final encrypted = await encryption.encryptMedia(base64Decode(bytes));
        final mediaId = const Uuid().v4();
        blobs.add((mediaId: mediaId, blob: encrypted.ciphertext));
        attachments.add({
          'id': attachmentId,
          'messageId': message['id'],
          'mediaId': mediaId,
          'mediaType': asset?['kind'] == 'audio' ? 'audio' : 'image',
          'encryptionKeyB64': base64Encode(encrypted.key),
          'contentHash': encrypted.ciphertextHash,
          'plaintextHash': encrypted.plaintextHash,
          'mimeType': asset?['mime_type'] ?? 'application/octet-stream',
          'sizeBytes': encrypted.ciphertext.length,
          'width': asset?['width'] ?? 0,
          'height': asset?['height'] ?? 0,
        });
      }
    }
    data['mediaAttachments'] = attachments;
    archive['mediaBindings'] = mediaBindings;
    // Retention uses the native import transaction/outbox, so data and its
    // preservation metadata commit or roll back together.
    return importer.importData(
      jsonEncode(data),
      mediaBlobs: blobs,
      preserveImportedOnboardingState: false,
      beforeRows: _removeTombstonedNativeRows,
      beforeCommit: () async {
        final current = (await exporter.buildExport()).toJson();
        final baseline = <String, dynamic>{};
        for (final entry in PluralPortMapper.collections.entries) {
          for (final row in PluralPortMapper.rows(current, entry.value)) {
            final key = '${entry.value}/${row['id']}';
            baseline[key] = existingIds.contains(key)
                ? desiredRows[key] ?? row
                : row;
          }
        }
        final boundIds = (archive['bindings'] as Map).values
            .expand((ids) => ids as List)
            .toSet();
        baseline.removeWhere(
          (key, row) => !boundIds.contains((row as Map)['id']),
        );
        archive['baseline'] = baseline;
        if (importSystemProfile) {
          archive['systemBaseline'] = PluralPortMapper.rows(
            current,
            'systemSettings',
          ).firstOrNull;
        }
        archive['warnings'] = plan.warnings;
        archive['imported_at'] = DateTime.now().toUtc().toIso8601String();
        await PluralPortPreservation(db).retain(archive);
      },
    );
  }

  Future<void> _removeTombstonedNativeRows(Json data) async {
    final members = await db.select(db.members).get();
    final groups = await db.select(db.memberGroups).get();
    final groupEntries = await db.select(db.memberGroupEntries).get();
    final fields = await db.select(db.customFields).get();
    final values = await db.select(db.customFieldValues).get();
    final notes = await db.select(db.notes).get();
    final sessions = await db.select(db.frontingSessions).get();
    final comments = await db.select(db.frontSessionComments).get();
    final conversations = await db.select(db.conversations).get();
    final messages = await db.select(db.chatMessages).get();
    final posts = await db.select(db.memberBoardPosts).get();
    final attachments = await db.select(db.mediaAttachments).get();

    Set<String> deletedIds(Iterable<dynamic> rows) => {
      for (final row in rows)
        if (row.isDeleted as bool) row.id as String,
    };
    String valueKey(String fieldId, String memberId) =>
        '$fieldId\u0000$memberId';
    void retain(String path, bool Function(Json row) keep) {
      PluralPortMapper.setRows(
        data,
        path,
        PluralPortMapper.rows(data, path).where(keep).toList(),
      );
    }

    final deletedMembers = deletedIds(members);
    final deletedGroups = deletedIds(groups);
    final deletedEntries = deletedIds(groupEntries);
    final deletedFields = deletedIds(fields);
    final deletedNotes = deletedIds(notes);
    final deletedSessions = deletedIds(sessions);
    final deletedComments = deletedIds(comments);
    final deletedConversations = deletedIds(conversations);
    final deletedMessages = deletedIds(messages);
    final deletedPosts = deletedIds(posts);
    final deletedAttachments = deletedIds(attachments);
    final deletedValueIds = deletedIds(values);
    final deletedValuePairs = {
      for (final value in values)
        if (value.isDeleted) valueKey(value.customFieldId, value.memberId),
    };

    retain('headmates', (row) => !deletedMembers.contains(row['id']));

    // Hierarchical groups and fields cannot outlive a deleted native parent.
    // Calculate the complete blocked subtree before removing its records.
    bool changed;
    do {
      changed = false;
      for (final group in PluralPortMapper.rows(data, 'memberGroups')) {
        if (deletedGroups.contains(group['id']) ||
            deletedGroups.contains(group['parentGroupId'])) {
          changed = deletedGroups.add(group['id'] as String) || changed;
        }
      }
    } while (changed);
    retain('memberGroups', (row) => !deletedGroups.contains(row['id']));
    retain(
      'memberGroupEntries',
      (row) =>
          !deletedEntries.contains(row['id']) &&
          !deletedGroups.contains(row['groupId']) &&
          !deletedMembers.contains(row['memberId']),
    );

    do {
      changed = false;
      for (final field in PluralPortMapper.rows(data, 'customFields')) {
        if (deletedFields.contains(field['id']) ||
            deletedFields.contains(field['parentFieldId'])) {
          changed = deletedFields.add(field['id'] as String) || changed;
        }
      }
    } while (changed);
    retain('customFields', (row) => !deletedFields.contains(row['id']));
    retain(
      'customFieldValues',
      (row) =>
          !deletedValueIds.contains(row['id']) &&
          !deletedFields.contains(row['customFieldId']) &&
          !deletedMembers.contains(row['memberId']) &&
          !deletedValuePairs.contains(
            valueKey(row['customFieldId'] as String, row['memberId'] as String),
          ),
    );

    retain('notes', (row) => !deletedNotes.contains(row['id']));
    final blockedSessions = {...deletedSessions};
    for (final session in PluralPortMapper.rows(data, 'frontSessions')) {
      if (blockedSessions.contains(session['id']) ||
          deletedMembers.contains(session['headmateId'])) {
        blockedSessions.add(session['id'] as String);
      }
    }
    retain(
      'frontSessions',
      (row) =>
          !blockedSessions.contains(row['id']) &&
          !deletedMembers.contains(row['headmateId']),
    );
    retain(
      'frontSessionComments',
      (row) =>
          !deletedComments.contains(row['id']) &&
          !blockedSessions.contains(row['sessionId']),
    );
    retain('conversations', (row) => !deletedConversations.contains(row['id']));
    final blockedMessages = {...deletedMessages};
    for (final message in PluralPortMapper.rows(data, 'messages')) {
      if (blockedMessages.contains(message['id']) ||
          deletedConversations.contains(message['conversationId'])) {
        blockedMessages.add(message['id'] as String);
      }
    }
    retain(
      'messages',
      (row) =>
          !blockedMessages.contains(row['id']) &&
          !deletedConversations.contains(row['conversationId']),
    );
    retain(
      'mediaAttachments',
      (row) =>
          !deletedAttachments.contains(row['id']) &&
          !blockedMessages.contains(row['messageId']),
    );
    retain('memberBoardPosts', (row) => !deletedPosts.contains(row['id']));
  }

  Future<PluralPortBundle> exportBundle() async {
    final preservation = PluralPortPreservation(db);
    var archives = await preservation.documents();
    final importedSystems =
        archives
            .where(
              (a) =>
                  a['kind'] == 'import' && a['systemProfileImported'] == true,
            )
            .toList()
          ..sort(
            (a, b) => (a['imported_at'] as String? ?? '').compareTo(
              b['imported_at'] as String? ?? '',
            ),
          );
    var systemId = importedSystems.isEmpty
        ? null
        : PluralPortMapper.rows(
                importedSystems.last['envelope'] as Json,
                'systems',
              ).firstOrNull?['id']
              as String?;
    final identity =
        archives
            .where((a) => a['kind'] == 'identity')
            .map((a) => a['id'] as String)
            .toList()
          ..sort();
    if (systemId == null && identity.isEmpty) {
      systemId = const Uuid().v4();
      await preservation.retain({'kind': 'identity', 'id': systemId});
      archives = await preservation.documents();
    }
    systemId ??= identity.first;
    final data = (await exporter.buildExport()).toJson();
    final codec = PluralPortExporter(data, systemId);
    final bundle = codec.build(archives);
    final directory = await supportDirectory();
    final assetRecords = bundle.envelope['assets'] as List;
    final messages = {
      for (final m in PluralPortMapper.rows(bundle.envelope, 'chat.messages'))
        m['id']: m,
    };
    for (final attachment in PluralPortMapper.rows(data, 'mediaAttachments')) {
      final mediaId = attachment['mediaId'] as String;
      if (mediaId.isEmpty) continue;
      final id = PluralPortMapper.stableId(
        'prism/media',
        attachment['id'] as String,
      );
      final existingAsset = assetRecords
          .cast<Json>()
          .where((a) => a['sha256'] == attachment['plaintextHash'])
          .firstOrNull;
      final exportAssetId = existingAsset?['id'] ?? id;
      if (existingAsset == null) {
        assetRecords.add({
          'id': id,
          'kind': attachment['mediaType'],
          'mime_type': attachment['mimeType'],
          'bundle_path': 'assets/${attachment['plaintextHash']}',
          'sha256': attachment['plaintextHash'],
          'width': attachment['width'],
          'height': attachment['height'],
        });
      }
      final asset = assetRecords.cast<Json>().firstWhere(
        (a) => a['id'] == exportAssetId,
      );
      final extensions =
          asset.putIfAbsent('extensions', () => <String, dynamic>{}) as Json;
      final prism =
          extensions.putIfAbsent('prism', () => <String, dynamic>{}) as Json;
      final associations =
          prism.putIfAbsent('media_attachments', () => <dynamic>[]) as List;
      final association = <String, dynamic>{
        'id': attachment['id'],
        'member_id': attachment['memberId'],
        'message_id': attachment['messageId'],
        'tag': attachment['tag'],
        'duration_ms': attachment['durationMs'],
        'waveform_b64': attachment['waveformB64'],
      };
      if (!associations.any(
        (a) => canonicalJson(a) == canonicalJson(association),
      )) {
        associations.add(association);
      }
      if (attachment['memberId'] != null) {
        (bundle.envelope['warnings'] as List).add({
          'level': 'warning',
          'code': 'member_media_archived',
          'message':
              'Member media is included with its Prism association metadata; other apps may not display it.',
        });
      }
      final message = messages[attachment['messageId']];
      if (message != null) {
        final linked =
            message.putIfAbsent('attachment_asset_ids', () => <dynamic>[])
                as List;
        if (!linked.contains(exportAssetId)) linked.add(exportAssetId);
      }
      final file = File('${directory.path}/prism_media/$mediaId.enc');
      try {
        if (await file.length() > PluralPortBundle.maxAsset + 1024) {
          throw const FormatException('Media exceeds the bundle asset limit.');
        }
        final bytes = await encryption.decryptMedia(
          ciphertext: await file.readAsBytes(),
          key: base64Decode(attachment['encryptionKeyB64'] as String),
          expectedCiphertextHash: attachment['contentHash'] as String,
          expectedPlaintextHash: attachment['plaintextHash'] as String,
        );
        final path = asset['bundle_path'] as String;
        asset['size_bytes'] = bytes.length;
        bundle.files[path] = bytes;
      } on FileSystemException {
        (bundle.envelope['warnings'] as List).add({
          'level': 'warning',
          'code': 'asset_bundle_missing',
          'message': 'Media ${attachment['id']} is not cached on this device.',
        });
      }
    }
    if (assetRecords.isNotEmpty) {
      final modules =
          (bundle.envelope['capabilities'] as Json)['modules'] as List;
      if (!modules.contains('assets')) modules.add('assets');
    }
    return bundle;
  }
}
