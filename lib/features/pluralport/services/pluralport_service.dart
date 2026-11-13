import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

/// Recovered bytes; an empty [mimeType] requests content sniffing.
class PluralPortRecoveredMedia {
  const PluralPortRecoveredMedia({required this.bytes, this.mimeType = ''});

  final Uint8List bytes;
  final String mimeType;
}

/// Authenticated recovery of a Prism media id, never an external URL.
class PluralPortMediaFetchRequest {
  const PluralPortMediaFetchRequest({
    required this.mediaId,
    required this.encryptionKeyB64,
    required this.contentHash,
    required this.plaintextHash,
  });

  final String mediaId;
  final String encryptionKeyB64;
  final String contentHash;
  final String plaintextHash;
}

/// Recovery failures become metadata-only warnings, not export failures.
class PluralPortRemoteMedia {
  const PluralPortRemoteMedia.ok(this.bytes) : failure = null;
  const PluralPortRemoteMedia.failed(this.failure) : bytes = null;

  final Uint8List? bytes;
  final String? failure;
}

typedef PluralPortMediaFetchFn =
    Future<PluralPortRemoteMedia> Function(PluralPortMediaFetchRequest request);

typedef PluralPortThumbnailFn =
    Future<PluralPortRecoveredMedia> Function(Uint8List original);

/// Caps for on-demand media recovery during an explicit export.
class PluralPortMediaRecoveryLimits {
  const PluralPortMediaRecoveryLimits({
    this.maxRemoteItems = 32,
    this.maxRemoteBytes = 32 * 1024 * 1024,
    this.remoteDeadline = const Duration(seconds: 45),
    this.maxGeneratedThumbnails = 200,
    this.maxBundleMediaBytes = 96 * 1024 * 1024,
  });

  final int maxRemoteItems;

  /// Maximum plaintext bytes accepted from recovery. The download manager's
  /// underlying request may receive one final blob before this limit is checked.
  final int maxRemoteBytes;

  /// Maximum time the export waits on remote recovery. A timed-out manager
  /// request can still complete its encrypted cache write in the background.
  final Duration remoteDeadline;

  final int maxGeneratedThumbnails;

  /// Media budget below [PluralPortBundle.maxExpanded], including thumbnails.
  final int maxBundleMediaBytes;
}

/// Authenticated downloads and local thumbnail generation for export recovery.
/// A null [PluralPortService.recovery] keeps export cache-only.
class PluralPortMediaRecovery {
  const PluralPortMediaRecovery({
    required this.fetch,
    required this.generateThumbnail,
    this.limits = const PluralPortMediaRecoveryLimits(),
  });

  final PluralPortMediaFetchFn fetch;
  final PluralPortThumbnailFn generateThumbnail;
  final PluralPortMediaRecoveryLimits limits;
}

/// Shared recovery and bundle budgets for one export.
class _ExportMediaState {
  _ExportMediaState(this.recovery, PluralPortBundle bundle)
    : limits = recovery?.limits ?? const PluralPortMediaRecoveryLimits(),
      _watch = Stopwatch()..start() {
    bundleBytes = bundle.files.values.fold(
      0,
      (total, bytes) => total + bytes.length,
    );
  }

  final PluralPortMediaRecovery? recovery;
  final PluralPortMediaRecoveryLimits limits;
  final Stopwatch _watch;

  int remoteAttempts = 0;
  int remoteBytes = 0;
  int generatedThumbnails = 0;
  int bundleBytes = 0;
  int omittedBundleItems = 0;
  int omittedBundleBytes = 0;

  /// Set once, so an exhausted cap produces one explanation instead of one per
  /// remaining attachment.
  bool remoteLimitReported = false;

  /// Whether another authenticated fetch fits the item, byte and time caps.
  bool get canFetchRemote =>
      recovery != null &&
      remoteAttempts < limits.maxRemoteItems &&
      remoteBytes < limits.maxRemoteBytes &&
      _watch.elapsed < limits.remoteDeadline;

  Duration get remainingRemoteTime => limits.remoteDeadline - _watch.elapsed;

  bool get canGenerateThumbnail =>
      recovery != null && generatedThumbnails < limits.maxGeneratedThumbnails;

  /// Reserve [length] bundle bytes for [path], or report that the media budget
  /// is exhausted. A path already in the bundle costs nothing.
  bool reserveMediaBytes(PluralPortBundle bundle, String path, int length) {
    if (bundle.files.containsKey(path)) return true;
    if (length > PluralPortBundle.maxAsset ||
        bundleBytes + length > limits.maxBundleMediaBytes) {
      omittedBundleItems += 1;
      omittedBundleBytes += length;
      return false;
    }
    bundleBytes += length;
    return true;
  }
}

class PluralPortService {
  PluralPortService({
    required this.db,
    required this.exporter,
    required this.importer,
    MediaEncryptionService? encryption,
    Future<Directory> Function()? supportDirectory,
    this.recovery,
  }) : encryption = encryption ?? MediaEncryptionService(),
       supportDirectory = supportDirectory ?? getApplicationSupportDirectory;
  final AppDatabase db;
  final DataExportService exporter;
  final DataImportService importer;
  final MediaEncryptionService encryption;
  final Future<Directory> Function() supportDirectory;

  /// Optional on-demand recovery for media the local cache no longer holds.
  /// Null keeps the export fully offline (cached bytes and metadata only).
  final PluralPortMediaRecovery? recovery;

  static PluralPortImportPlan previewBytes(Uint8List bytes) =>
      PluralPortMapper.plan(PluralPortBundle.decode(bytes));
  Future<PluralPortImportPlan> preview(Uint8List bytes) =>
      compute(previewBytes, bytes);

  Future<ImportResult> importPlan(
    PluralPortImportPlan plan, {
    bool importSystemProfile = false,
    bool restorePrismPreferences = false,
  }) async {
    PluralPortMapper.validateExtensions(plan.archive['envelope'] as Json);
    final existingNative = (await exporter.buildExport()).toJson();
    final existingIds = <String>{
      for (final key in PluralPortMapper.collections.values)
        for (final row in PluralPortMapper.rows(existingNative, key))
          '$key/${row['id']}',
    };
    // Storage canonicalizes what an import writes (timestamps lose sub-second
    // precision, JSON is re-serialized, image assets are rebuilt). Earlier
    // imports recorded that canonical post-import state as their baseline, so a
    // repeat import compares stored rows against stored rows; using the
    // source-shaped plan rows here would report every unchanged record as a
    // local edit and drop the preserved source out of export.
    final previousBaselines = _recordedBaselines(existingNative);
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
          (extensionObject(envelope['extensions'])?['prism']
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
      final prism = extensionObject(asset['extensions'])?['prism'] as Map?;
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
            // An existing native row was not rewritten by this import, so its
            // canonical state comes from the baseline an earlier import
            // recorded. Falling back to the plan row keeps records Prism never
            // imported comparable against their source shape.
            baseline[key] = existingIds.contains(key)
                ? previousBaselines[key] ?? desiredRows[key] ?? row
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

  /// The native rows storage kept right after an earlier import, keyed the way
  /// an archive baseline is (`collection/nativeId`). A later import of the same
  /// origin compares live rows against these, never against the shape the
  /// source file used, so canonicalization is not mistaken for a local edit.
  /// Newer archives win, matching the snapshot export uses for an origin.
  static Map<String, Json> _recordedBaselines(Json existingNative) {
    final baselines = <String, Json>{};
    final archives =
        (existingNative['pluralPortArchives'] as List? ?? const [])
            .whereType<Map>()
            .where((a) => a['kind'] == 'import' && a['baseline'] is Map)
            .toList()
          ..sort(
            (a, b) => (a['imported_at'] as String? ?? '').compareTo(
              b['imported_at'] as String? ?? '',
            ),
          );
    for (final archive in archives) {
      for (final entry in (archive['baseline'] as Map).entries) {
        final key = entry.key;
        final row = entry.value;
        if (key is String && row is Map) {
          baselines[key] = row.cast<String, dynamic>();
        }
      }
    }
    return baselines;
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
      final prism = extensionObject(asset['extensions'])?['prism'] as Map?;
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
    final messages = <String, Json>{
      for (final m in PluralPortMapper.rows(bundle.envelope, 'chat.messages'))
        m['id'] as String: m,
    };
    // Share budgets across attachments; unresolved media remains metadata-only.
    final mediaState = _ExportMediaState(recovery, bundle);
    for (final attachment in PluralPortMapper.rows(data, 'mediaAttachments')) {
      await _addAttachmentMedia(
        bundle: bundle,
        assetRecords: assetRecords,
        previousAssociations: previousAssociations,
        messages: messages,
        directory: directory,
        state: mediaState,
        attachment: attachment,
      );
    }
    if (mediaState.omittedBundleItems > 0) {
      (bundle.envelope['warnings'] as List).add({
        'level': 'warning',
        'code': 'asset_bundle_omitted',
        'message':
            '${mediaState.omittedBundleItems} media item(s) '
            '(${mediaState.omittedBundleBytes} bytes) were omitted because '
            'this export reached its media size limit.',
      });
    }
    _repairAbsentDeclarations(bundle);
    if (assetRecords.isNotEmpty) {
      final modules =
          (bundle.envelope['capabilities'] as Json)['modules'] as List;
      if (!modules.contains('assets')) modules.add('assets');
    }
    return bundle;
  }

  /// Add one native attachment's original, thumbnail and metadata to [bundle].
  ///
  /// Local-first: the cached encrypted blob, then — only when a
  /// [PluralPortMediaRecovery] is wired and the budgets allow — the app's
  /// authenticated sync download. A missing image thumbnail is regenerated from
  /// the verified original rather than left empty. Every failure becomes a
  /// warning, and a blob that never resolves is exported as metadata only: the
  /// export never declares a path, hash or size for bytes it does not hold.
  Future<void> _addAttachmentMedia({
    required PluralPortBundle bundle,
    required List assetRecords,
    required Map<String, Json> previousAssociations,
    required Map<String, Json> messages,
    required Directory directory,
    required _ExportMediaState state,
    required Json attachment,
  }) async {
    final attachmentId = attachment['id'] as String;
    final mediaType = attachment['mediaType'] as String? ?? '';
    final mediaId = attachment['mediaId'] as String? ?? '';
    final encryptionKeyB64 = attachment['encryptionKeyB64'] as String? ?? '';
    final contentHash = attachment['contentHash'] as String? ?? '';
    final plaintextHash = attachment['plaintextHash'] as String? ?? '';
    final sourceUrl = attachment['sourceUrl'] as String? ?? '';
    final rowMime = attachment['mimeType'] as String? ?? '';
    final warnings = bundle.envelope['warnings'] as List;
    final id = PluralPortMapper.stableId('prism/media', attachmentId);

    // Remote recovery requires a Prism id and complete integrity metadata.
    var original = await _cachedPlaintext(
      directory: directory,
      mediaId: mediaId,
      encryptionKeyB64: encryptionKeyB64,
      ciphertextHash: contentHash,
      plaintextHash: plaintextHash,
    );
    var recoveredFromSync = false;
    if (original.bytes == null && mediaId.isNotEmpty) {
      final remote = await _remotePlaintext(
        state: state,
        mediaId: mediaId,
        encryptionKeyB64: encryptionKeyB64,
        contentHash: contentHash,
        plaintextHash: plaintextHash,
      );
      if (remote.bytes != null || remote.failure != null) {
        original = remote;
        recoveredFromSync = remote.bytes != null;
      }
    }
    final Uint8List? bytes = original.bytes;
    if (recoveredFromSync) {
      warnings.add({
        'level': 'info',
        'code': 'asset_media_recovered',
        'message': 'Media $attachmentId was fetched from sync for this export.',
      });
    }

    final existingAsset = assetRecords
        .cast<Json>()
        .where(
          (a) =>
              (plaintextHash.isNotEmpty && a['sha256'] == plaintextHash) ||
              // URL-only media has no content hash. Reuse its stable asset
              // identity when re-exporting a previously imported archive.
              (mediaId.isEmpty && a['id'] == id),
        )
        .firstOrNull;
    final exportAssetId = existingAsset?['id'] ?? id;
    final Json asset;
    if (existingAsset == null) {
      asset = <String, dynamic>{
        'id': id,
        'kind': mediaType == 'gif' ? 'video' : mediaType,
        'source_refs': [
          {'app': 'prism', 'collection': 'assets', 'id': id},
        ],
      };
      assetRecords.add(asset);
    } else {
      asset = existingAsset;
    }
    asset['width'] = attachment['width'];
    asset['height'] = attachment['height'];

    String? storedPath;
    if (bytes != null) {
      final digest = sha256.convert(bytes).toString();
      final path = 'assets/$digest';
      if (state.reserveMediaBytes(bundle, path, bytes.length)) {
        bundle.files[path] = bytes;
        storedPath = path;
        asset['bundle_path'] = path;
        asset['sha256'] = digest;
        asset['size_bytes'] = bytes.length;
        asset['mime_type'] = _sniffMediaMime(bytes, fallback: rowMime);
        asset.remove('data_base64');
        asset.remove('data_uri');
      }
    }
    if (storedPath == null) {
      final retained = _resolvedAssetBytes(bundle, asset) != null;
      if (!retained) {
        asset.remove('bundle_path');
        asset.remove('sha256');
        asset.remove('size_bytes');
      }
      if (rowMime.isNotEmpty && asset['mime_type'] == null) {
        asset['mime_type'] = rowMime;
      }
      if (mediaId.isEmpty && sourceUrl.isNotEmpty) asset['uri'] = sourceUrl;
      if (mediaId.isNotEmpty && !retained) {
        final reason = bytes != null
            ? 'bundle_budget_exhausted'
            : original.failure ?? 'bytes_not_on_this_device';
        _markUnavailable(asset, mediaId, reason);
        if (bytes == null) {
          warnings.add({
            'level': 'warning',
            'code': 'asset_bundle_missing',
            'message': 'Media $attachmentId is not cached on this device.',
          });
        }
        if (state.recovery != null &&
            !state.canFetchRemote &&
            !state.remoteLimitReported) {
          state.remoteLimitReported = true;
          warnings.add({
            'level': 'warning',
            'code': 'asset_recovery_skipped',
            'message':
                'Some media was not recovered: this export reached its '
                'recovery limit.',
          });
        }
      }
    }

    final extensions =
        extensionObject(asset['extensions']) ?? <String, dynamic>{};
    asset['extensions'] = extensions;
    final prism =
        extensions.putIfAbsent('prism', () => <String, dynamic>{}) as Json;
    final associations =
        prism.putIfAbsent('media_attachments', () => <dynamic>[]) as List;
    final previous = previousAssociations[attachmentId] ?? {};
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
      'id': attachmentId,
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

    // Regenerate thumbnails locally from verified originals, without another fetch.
    final thumbnailId = attachment['thumbnailMediaId'] as String? ?? '';
    final thumbnailContentHash =
        attachment['thumbnailContentHash'] as String? ?? '';
    final thumbnailPlaintextHash =
        attachment['thumbnailPlaintextHash'] as String? ?? '';
    final wantsThumbnail =
        (mediaType == 'image' || mediaType == 'gif') &&
        (thumbnailId.isNotEmpty ||
            (thumbnailContentHash.isNotEmpty &&
                thumbnailPlaintextHash.isNotEmpty));
    Uint8List? thumbnail;
    var generatedThumbnail = false;
    var generatedMime = '';
    if (wantsThumbnail) {
      if (thumbnailId.isNotEmpty) {
        thumbnail = (await _cachedPlaintext(
          directory: directory,
          mediaId: thumbnailId,
          encryptionKeyB64: encryptionKeyB64,
          ciphertextHash: thumbnailContentHash,
          plaintextHash: thumbnailPlaintextHash,
        )).bytes;
      }
      if (thumbnail == null && bytes != null && state.canGenerateThumbnail) {
        state.generatedThumbnails += 1;
        try {
          final generated = await state.recovery!.generateThumbnail(bytes);
          if (generated.bytes.isNotEmpty) {
            thumbnail = generated.bytes;
            generatedMime = generated.mimeType;
            generatedThumbnail = true;
          }
        } on Object {
          // A codec failure is a missing thumbnail, never a failed export.
          thumbnail = null;
        }
      }
    }

    final thumbnailAssetId = PluralPortMapper.stableId(
      'prism/thumbnail',
      attachmentId,
    );
    var storedThumbnail = false;
    if (thumbnail != null) {
      final digest = sha256.convert(thumbnail).toString();
      final path = 'assets/$digest';
      if (state.reserveMediaBytes(bundle, path, thumbnail.length)) {
        bundle.files[path] = thumbnail;
        storedThumbnail = true;
        final record = assetRecords.cast<Json>().firstWhere(
          (a) => a['id'] == thumbnailAssetId,
          orElse: () {
            final created = <String, dynamic>{
              'id': thumbnailAssetId,
              'source_refs': [
                {
                  'app': 'prism',
                  'collection': 'assets',
                  'id': thumbnailAssetId,
                },
              ],
            };
            assetRecords.add(created);
            return created;
          },
        );
        record['kind'] = 'image';
        record['bundle_path'] = path;
        record['sha256'] = digest;
        record['size_bytes'] = thumbnail.length;
        record['mime_type'] = _sniffMediaMime(
          thumbnail,
          fallback: generatedMime.isNotEmpty ? generatedMime : 'image/jpeg',
        );
        record.remove('data_base64');
        record.remove('data_uri');
        association['thumbnail_asset_id'] = thumbnailAssetId;
        if (generatedThumbnail) {
          warnings.add({
            'level': 'info',
            'code': 'asset_thumbnail_generated',
            'message':
                'Thumbnail $attachmentId was generated from the original for '
                'this export.',
          });
        }
      }
    }
    if (!storedThumbnail) {
      // Nothing to point at: drop a stale link, but keep one that still
      // resolves inside the archive (a retained source thumbnail).
      final previousThumbnail = previous['thumbnail_asset_id'];
      final keepPrevious =
          previousThumbnail is String &&
          assetRecords.cast<Json>().any(
            (a) =>
                a['id'] == previousThumbnail &&
                _resolvedAssetBytes(bundle, a) != null,
          );
      if (!keepPrevious) association.remove('thumbnail_asset_id');
      if (wantsThumbnail && thumbnail == null && !keepPrevious) {
        warnings.add({
          'level': 'warning',
          'code': 'asset_bundle_missing',
          'message': 'Thumbnail $attachmentId is not cached on this device.',
        });
      }
    }

    if (!associations.any(
      (a) => canonicalJson(a) == canonicalJson(association),
    )) {
      associations.add(association);
    }
    if (attachment['memberId'] != null) {
      warnings.add({
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
    if (mediaId.isEmpty && storedPath == null) {
      // URL-only media keeps its reference; there are no local bytes to export.
      return;
    }
  }

  /// Decrypt one cached blob, verifying both digests. Returns a null result
  /// with an optional reason instead of throwing: a missing, oversized,
  /// unreadable or tampered blob is an export warning, not an export failure.
  Future<({Uint8List? bytes, String? failure})> _cachedPlaintext({
    required Directory directory,
    required String mediaId,
    required String encryptionKeyB64,
    required String ciphertextHash,
    required String plaintextHash,
  }) async {
    if (mediaId.isEmpty ||
        encryptionKeyB64.isEmpty ||
        ciphertextHash.isEmpty ||
        plaintextHash.isEmpty) {
      return (bytes: null, failure: null);
    }
    final file = File('${directory.path}/prism_media/$mediaId.enc');
    Uint8List? ciphertext;
    try {
      ciphertext = await file.length() > PluralPortBundle.maxAsset + 1024
          ? null
          : await file.readAsBytes();
    } on FileSystemException {
      return (bytes: null, failure: null);
    }
    if (ciphertext == null) {
      return (bytes: null, failure: 'blob_too_large');
    }
    return _decryptVerified(
      ciphertext: ciphertext,
      encryptionKeyB64: encryptionKeyB64,
      ciphertextHash: ciphertextHash,
      plaintextHash: plaintextHash,
    );
  }

  /// Ask the injected recovery source for one blob, within the shared caps.
  Future<({Uint8List? bytes, String? failure})> _remotePlaintext({
    required _ExportMediaState state,
    required String mediaId,
    required String encryptionKeyB64,
    required String contentHash,
    required String plaintextHash,
  }) async {
    final recovery = state.recovery;
    if (recovery == null ||
        !state.canFetchRemote ||
        mediaId.isEmpty ||
        encryptionKeyB64.isEmpty ||
        contentHash.isEmpty ||
        plaintextHash.isEmpty) {
      return (bytes: null, failure: null);
    }
    state.remoteAttempts += 1;
    PluralPortRemoteMedia fetched;
    try {
      fetched = await recovery
          .fetch(
            PluralPortMediaFetchRequest(
              mediaId: mediaId,
              encryptionKeyB64: encryptionKeyB64,
              contentHash: contentHash,
              plaintextHash: plaintextHash,
            ),
          )
          .timeout(state.remainingRemoteTime);
    } on TimeoutException {
      return (bytes: null, failure: 'recovery_deadline');
    } on Object {
      return (bytes: null, failure: 'fetch_failed');
    }
    final bytes = fetched.bytes;
    if (bytes == null) {
      return (bytes: null, failure: fetched.failure ?? 'unavailable');
    }
    // Count even rejected bytes so oversized or corrupt responses cannot
    // repeatedly consume recovery work under the same byte budget.
    state.remoteBytes += bytes.length;
    if (bytes.length > PluralPortBundle.maxAsset ||
        state.remoteBytes > state.limits.maxRemoteBytes) {
      return (bytes: null, failure: 'remote_byte_limit');
    }
    // Verify the plaintext digest even when the recovery adapter reports success.
    if (sha256.convert(bytes).toString() != plaintextHash) {
      return (bytes: null, failure: 'integrity');
    }
    return (bytes: bytes, failure: null);
  }

  Future<({Uint8List? bytes, String? failure})> _decryptVerified({
    required Uint8List ciphertext,
    required String encryptionKeyB64,
    required String ciphertextHash,
    required String plaintextHash,
  }) async {
    final Uint8List key;
    try {
      key = base64Decode(encryptionKeyB64);
    } on FormatException {
      return (bytes: null, failure: 'invalid_key');
    }
    try {
      final plaintext = await encryption.decryptMedia(
        ciphertext: ciphertext,
        key: key,
        expectedCiphertextHash: ciphertextHash,
        expectedPlaintextHash: plaintextHash,
      );
      return (bytes: plaintext, failure: null);
    } on StateError {
      return (bytes: null, failure: 'integrity');
    } on Object {
      return (bytes: null, failure: 'decrypt_failed');
    }
  }

  /// Bytes this asset still resolves to *inside the archive*: a bundled file, a
  /// retained source file, or inline base64/data URI. Null means the record
  /// declares nothing this archive can produce.
  Uint8List? _resolvedAssetBytes(PluralPortBundle bundle, Json asset) {
    try {
      return bundle.assetBytes(asset);
    } on Object {
      return null;
    }
  }

  /// Record why a media asset carries metadata but no bytes.
  void _markUnavailable(Json asset, String mediaId, String reason) {
    final extensions =
        extensionObject(asset['extensions']) ?? <String, dynamic>{};
    asset['extensions'] = extensions;
    final prism =
        extensions.putIfAbsent('prism', () => <String, dynamic>{}) as Json;
    prism['unavailable'] = {'reason': reason, 'media_id': mediaId};
  }

  /// Safety net over all live and retained media records: a declaration that does not
  /// resolve inside the archive is metadata-only from now on. This is what keeps
  /// a legacy record (or an older export) from shipping `assets/null`-shaped
  /// declarations, and it can only ever remove fields.
  void _repairAbsentDeclarations(PluralPortBundle bundle) {
    final warnings = bundle.envelope['warnings'] as List;
    for (final asset in PluralPortMapper.rows(bundle.envelope, 'assets')) {
      if (_resolvedAssetBytes(bundle, asset) != null) continue;
      final extensions = extensionObject(asset['extensions']);
      final sheaf = extensions?['sheaf'];
      final legacyPath = sheaf is Map ? sheaf['bundle_path'] : null;
      final hasDeclaration =
          asset['bundle_path'] != null ||
          legacyPath != null ||
          asset['data_base64'] != null ||
          asset['data_uri'] != null;
      if (!hasDeclaration) continue;
      final retainedEvidence = <String, dynamic>{
        'bundle_path': asset['bundle_path'],
        'sheaf_bundle_path': legacyPath,
        'sha256': asset['sha256'],
        'size_bytes': asset['size_bytes'],
      }..removeWhere((key, value) => value == null);
      asset.remove('bundle_path');
      if (sheaf is Map) sheaf.remove('bundle_path');
      asset.remove('sha256');
      asset.remove('size_bytes');
      asset.remove('data_base64');
      asset.remove('data_uri');
      final mediaId = asset['id'] as String;
      _markUnavailable(asset, mediaId, 'declared_bytes_unusable');
      final prism = (asset['extensions'] as Json)['prism'] as Json;
      prism.putIfAbsent('unusable_media_declaration', () => retainedEvidence);
      warnings.add({
        'level': 'warning',
        'code': 'export_self_check',
        'message':
            'Asset $mediaId declared bytes that could not be verified; it was '
            'exported as metadata only.',
      });
    }
  }

  /// Problems with a bundle's own media declarations, checked before encoding:
  /// every declared path must name a file in the bundle. Empty means the
  /// archive is self-consistent.
  static List<String> validateBundle(PluralPortBundle bundle) {
    final problems = <String>[];
    var expandedBytes = 0;
    for (final entry in bundle.files.entries) {
      expandedBytes += entry.value.length;
      if (entry.value.length > PluralPortBundle.maxAsset) {
        problems.add(
          '${entry.key} exceeds the per-file size limit. '
          'Create a native Prism backup to preserve your data instead.',
        );
      }
    }
    if (expandedBytes > PluralPortBundle.maxExpanded) {
      problems.add(
        'Bundled files exceed the expanded archive size limit. '
        'Create a native Prism backup to preserve your data instead.',
      );
    }
    for (final asset in PluralPortMapper.rows(bundle.envelope, 'assets')) {
      String? declared;
      try {
        declared = PluralPortBundle.declaredBundlePath(asset);
      } on FormatException {
        problems.add('Asset ${asset['id']} declares a malformed bundle_path.');
        continue;
      }
      if (declared == null) continue;
      if (!bundle.files.containsKey(declared)) {
        problems.add(
          'Asset ${asset['id']} declares $declared, which is not in the bundle.',
        );
      }
    }
    return problems;
  }

  /// Mime type from the bytes themselves, so a generated thumbnail is labelled
  /// with what it actually is (the codec emits WebP for alpha sources).
  static String _sniffMediaMime(Uint8List bytes, {String fallback = ''}) {
    bool startsWith(List<int> signature) {
      if (bytes.length < signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[i] != signature[i]) return false;
      }
      return true;
    }

    if (startsWith([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (startsWith([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        startsWith([0x52, 0x49, 0x46, 0x46]) &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (startsWith([0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      final brand = String.fromCharCodes(bytes.sublist(8, 12));
      return switch (brand) {
        'avif' || 'avis' => 'image/avif',
        'heic' || 'heix' || 'hevc' || 'hevx' => 'image/heic',
        'mif1' || 'msf1' => 'image/heif',
        'M4A ' || 'M4B ' => 'audio/mp4',
        'qt  ' => 'video/quicktime',
        _ => fallback.isNotEmpty ? fallback : 'video/mp4',
      };
    }
    if (startsWith([0x4F, 0x67, 0x67, 0x53])) return 'audio/ogg';
    if (bytes.length >= 12 &&
        startsWith([0x52, 0x49, 0x46, 0x46]) &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WAVE') {
      return 'audio/wav';
    }
    return fallback.isNotEmpty ? fallback : 'application/octet-stream';
  }
}
