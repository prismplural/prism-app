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

import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/domain/preferences/preference_entity_id.dart';

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
    bool restorePrismPreferences = false,
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
    if ((existingNative['pluralPortArchives'] as List? ?? [])
        .whereType<Map>()
        .any(
          (a) =>
              a['namespace'] == archive['namespace'] &&
              a['prismPreferencesRestored'] == true,
        )) {
      archive['prismPreferencesRestored'] = true;
    }
    final envelope = archive['envelope'] as Json;
    final files = archive['files'] as Json;
    final assets = {
      for (final a in PluralPortMapper.rows(envelope, 'assets')) a['id']: a,
    };
    if (restorePrismPreferences) {
      final modules =
          ((envelope['extensions'] as Map?)?['prism']
                  as Map?)?['native_modules']
              as Map?;
      final savedSettings = (modules?['systemSettings'] as List?)
          ?.whereType<Map>()
          .firstOrNull;
      final current =
          PluralPortMapper.rows(existingNative, 'systemSettings').firstOrNull ??
          <String, dynamic>{};
      if (savedSettings != null) {
        data['systemSettings'] = [
          {
            ...current,
            for (final key in PluralPortMapper.portableSettingKeys)
              if (savedSettings.containsKey(key)) key: savedSettings[key],
          },
        ];
      }
      final knownKeys = appPreferenceRegistry.definitions
          .map((d) => PreferenceEntityId.app(d.key))
          .toSet();
      data['appPreferences'] = [
        for (final row in (modules?['appPreferences'] as List? ?? []))
          if (row is Map && knownKeys.contains(row['key']))
            PluralPortMapper.clone(row.cast<String, dynamic>()),
      ];
      archive['prismPreferencesRestored'] = true;
    }
    if (importSystemProfile) {
      final system = PluralPortMapper.rows(envelope, 'systems').firstOrNull;
      if (system != null) {
        final current =
            PluralPortMapper.rows(data, 'systemSettings').firstOrNull ??
            PluralPortMapper.rows(
              existingNative,
              'systemSettings',
            ).firstOrNull ??
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
    final mediaBindings = <String, List<String>>{};
    final restoredAssociations = <String>[];
    final messages = PluralPortMapper.rows(
      data,
      'messages',
    ).map((r) => r['id']).toSet();
    final members = PluralPortMapper.rows(
      data,
      'headmates',
    ).map((r) => r['id']).toSet();
    final processedAttachments = <String>{};

    Future<void> restoreMedia(Json asset, Json association) async {
      final id = association['id'];
      if (id is! String || id.isEmpty || !processedAttachments.add(id)) return;
      final messageId = association['message_id'] as String? ?? '';
      final memberId = association['member_id'] as String? ?? '';
      if (messageId.isNotEmpty && !messages.contains(messageId)) return;
      if (memberId.isNotEmpty && !members.contains(memberId)) return;
      if (messageId.isEmpty && memberId.isEmpty) return;
      final mediaType = association['media_type'] ?? asset['kind'];
      if (!['image', 'audio', 'gif'].contains(mediaType)) return;
      final encoded = files[asset['bundle_path']];
      final sourceUrl = association['source_url'] as String? ?? '';
      if (encoded is! String && !(mediaType == 'gif' && sourceUrl.isNotEmpty)) {
        return;
      }
      restoredAssociations.add(id);
      if (messageId.isNotEmpty) {
        mediaBindings
            .putIfAbsent('$messageId/${asset['id']}', () => [])
            .add(id);
      }
      final existing = await (db.select(
        db.mediaAttachments,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (existing != null) return;
      final row = <String, dynamic>{
        ...((association['native'] as Map?)?.cast<String, dynamic>() ?? {}),
        'id': id,
        'messageId': messageId,
        'memberId': memberId,
        'tag': association['tag'] ?? '',
        'mediaId': '',
        'mediaType': mediaType,
        'encryptionKeyB64': '',
        'contentHash': '',
        'plaintextHash': '',
        'mimeType':
            association['mime_type'] ??
            asset['mime_type'] ??
            'application/octet-stream',
        'sizeBytes': 0,
        'width': association['width'] ?? asset['width'] ?? 0,
        'height': association['height'] ?? asset['height'] ?? 0,
        'durationMs': association['duration_ms'] ?? 0,
        'waveformB64': association['waveform_b64'] ?? '',
        'blurhash': association['blurhash'] ?? '',
        'sourceUrl': sourceUrl,
        'previewUrl': association['preview_url'] ?? '',
      };
      if (encoded is String) {
        final encrypted = await encryption.encryptMedia(base64Decode(encoded));
        final mediaId = const Uuid().v4();
        blobs.add((mediaId: mediaId, blob: encrypted.ciphertext));
        row.addAll({
          'mediaId': mediaId,
          'encryptionKeyB64': base64Encode(encrypted.key),
          'contentHash': encrypted.ciphertextHash,
          'plaintextHash': encrypted.plaintextHash,
          'sizeBytes': encrypted.ciphertext.length,
        });
        final thumbnail = assets[association['thumbnail_asset_id']];
        final thumbnailBytes = files[thumbnail?['bundle_path']];
        if (thumbnailBytes is String) {
          final encryptedThumbnail = await encryption.encryptMediaWithKey(
            base64Decode(thumbnailBytes),
            encrypted.key,
          );
          final thumbnailId = const Uuid().v4();
          blobs.add((
            mediaId: thumbnailId,
            blob: encryptedThumbnail.ciphertext,
          ));
          row.addAll({
            'thumbnailMediaId': thumbnailId,
            'thumbnailContentHash': encryptedThumbnail.ciphertextHash,
            'thumbnailPlaintextHash': encryptedThumbnail.plaintextHash,
          });
        }
      }
      attachments.add(row);
    }

    for (final asset in assets.values) {
      final prism = (asset['extensions'] as Map?)?['prism'] as Map?;
      for (final association in (prism?['media_attachments'] as List? ?? [])) {
        if (association is Map) {
          await restoreMedia(asset, association.cast<String, dynamic>());
        }
      }
    }
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
        if (mediaBindings.containsKey('${message['id']}/$assetId')) continue;
        final asset = assets[assetId];
        if (asset == null) continue;
        await restoreMedia(asset, {
          'id': PluralPortMapper.stableId(
            message['id'] as String,
            assetId as String,
          ),
          'message_id': message['id'],
        });
      }
    }
    archive['mediaAssociations'] = restoredAssociations;
    data['mediaAttachments'] = attachments;
    archive['mediaBindings'] = mediaBindings;
    // Retention uses the native import transaction/outbox, so data and its
    // preservation metadata commit or roll back together.
    return importer.importData(
      jsonEncode(data),
      mediaBlobs: blobs,
      preserveImportedOnboardingState: false,
      preserveCurrentDeviceSettings: true,
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
        archive['nativeModuleBindings'] = {
          for (final key in PluralPortMapper.nativeModuleKeys)
            key: PluralPortMapper.rows(
              plan.native,
              key,
            ).map((r) => r['id']).toList(),
        };

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
    final reminders = await db.select(db.reminders).get();
    final categories = await db.select(db.conversationCategories).get();
    final friends = await db.select(db.friends).get();

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

    retain('reminders', (row) => !deletedIds(reminders).contains(row['id']));
    retain(
      'conversationCategories',
      (row) => !deletedIds(categories).contains(row['id']),
    );
    retain('friends', (row) => !deletedIds(friends).contains(row['id']));
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
    final liveAttachmentIds = PluralPortMapper.rows(
      data,
      'mediaAttachments',
    ).map((r) => r['id']).toSet();
    final previousAssociations = <String, Json>{};
    for (final asset in assetRecords.whereType<Map>()) {
      final prism = (asset['extensions'] as Map?)?['prism'] as Map?;
      final associations = prism?['media_attachments'];
      if (associations is! List) continue;
      final retained = <dynamic>[];
      for (final association in associations) {
        if (association is Map &&
            liveAttachmentIds.contains(association['id'])) {
          previousAssociations[association['id'] as String] = association
              .cast<String, dynamic>();
        } else {
          retained.add(association);
        }
      }
      prism!['media_attachments'] = retained;
    }
    final messages = {
      for (final m in PluralPortMapper.rows(bundle.envelope, 'chat.messages'))
        m['id']: m,
    };
    for (final attachment in PluralPortMapper.rows(data, 'mediaAttachments')) {
      final mediaId = attachment['mediaId'] as String;
      final id = PluralPortMapper.stableId(
        'prism/media',
        attachment['id'] as String,
      );
      final existingAsset = assetRecords
          .cast<Json>()
          .where(
            (a) =>
                (attachment['plaintextHash'] as String? ?? '').isNotEmpty &&
                a['sha256'] == attachment['plaintextHash'],
          )
          .firstOrNull;
      final exportAssetId = existingAsset?['id'] ?? id;
      if (existingAsset == null) {
        assetRecords.add({
          'id': id,
          'kind': attachment['mediaType'] == 'gif'
              ? 'video'
              : attachment['mediaType'],
          'source_refs': [
            {'app': 'prism', 'collection': 'assets', 'id': id},
          ],
          'mime_type': attachment['mimeType'],
          if (mediaId.isNotEmpty)
            'bundle_path': 'assets/${attachment['plaintextHash']}',
          if (mediaId.isEmpty) 'uri': attachment['sourceUrl'],
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
      final previous = previousAssociations[attachment['id']] ?? {};
      final association = <String, dynamic>{
        ...previous,
        'native': {
          ...((previous['native'] as Map?)?.cast<String, dynamic>() ?? {}),
          for (final entry in attachment.entries)
            if (!const {
              'mediaId',
              'encryptionKeyB64',
              'contentHash',
              'plaintextHash',
              'thumbnailMediaId',
              'thumbnailContentHash',
              'thumbnailPlaintextHash',
            }.contains(entry.key))
              entry.key: entry.value,
        },
        'id': attachment['id'],
        'member_id': attachment['memberId'],
        'message_id': attachment['messageId'],
        'tag': attachment['tag'],
        'duration_ms': attachment['durationMs'],
        'waveform_b64': attachment['waveformB64'],
        'media_type': attachment['mediaType'],
        'blurhash': attachment['blurhash'],
        'source_url': attachment['sourceUrl'],
        'preview_url': attachment['previewUrl'],
        'width': attachment['width'],
        'height': attachment['height'],
        'mime_type': attachment['mimeType'],
      };
      final thumbnailId = attachment['thumbnailMediaId'] as String? ?? '';
      if (thumbnailId.isNotEmpty) {
        final thumbnailAssetId = PluralPortMapper.stableId(
          'prism/thumbnail',
          attachment['id'] as String,
        );
        final thumbnailPath = 'assets/${attachment['thumbnailPlaintextHash']}';
        association['thumbnail_asset_id'] = thumbnailAssetId;
        if (!assetRecords.cast<Json>().any(
          (a) => a['id'] == thumbnailAssetId,
        )) {
          assetRecords.add({
            'id': thumbnailAssetId,
            'source_refs': [
              {'app': 'prism', 'collection': 'assets', 'id': thumbnailAssetId},
            ],
            'kind': 'image',
            'mime_type': 'image/jpeg',
            'bundle_path': thumbnailPath,
            'sha256': attachment['thumbnailPlaintextHash'],
          });
        }
        try {
          final thumbnailFile = File(
            '${directory.path}/prism_media/$thumbnailId.enc',
          );
          if (await thumbnailFile.length() > PluralPortBundle.maxAsset + 1024) {
            throw const FormatException(
              'Thumbnail exceeds the bundle asset limit.',
            );
          }
          bundle.files[thumbnailPath] = await encryption.decryptMedia(
            ciphertext: await thumbnailFile.readAsBytes(),
            key: base64Decode(attachment['encryptionKeyB64'] as String),
            expectedCiphertextHash:
                attachment['thumbnailContentHash'] as String,
            expectedPlaintextHash:
                attachment['thumbnailPlaintextHash'] as String,
          );
        } on FileSystemException {
          (bundle.envelope['warnings'] as List).add({
            'level': 'warning',
            'code': 'asset_bundle_missing',
            'message':
                'Thumbnail ${attachment['id']} is not cached on this device.',
          });
        }
      }
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
      if (mediaId.isEmpty) continue;
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
