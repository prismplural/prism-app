import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';

typedef PkGroupCatchupRecordCallback =
    Future<void> Function({
      required String table,
      required String entityId,
      required Map<String, dynamic> fields,
    });

class PkGroupSyncV2CatchupService {
  const PkGroupSyncV2CatchupService({
    required AppDatabase db,
    required PkGroupCatchupRecordCallback recordGroupUpdate,
    required PkGroupCatchupRecordCallback recordEntryCreate,
    SharedPreferences? preferences,
  }) : _db = db,
       _recordGroupUpdate = recordGroupUpdate,
       _recordEntryCreate = recordEntryCreate,
       _preferences = preferences;

  static const flagKey = 'sync.pk_group_sync_v2_catchup_v1';
  static const _groupTable = 'member_groups';
  static const _entryTable = 'member_group_entries';
  static const _lookupBatchSize = 500;

  final AppDatabase _db;
  final PkGroupCatchupRecordCallback _recordGroupUpdate;
  final PkGroupCatchupRecordCallback _recordEntryCreate;
  final SharedPreferences? _preferences;

  Future<PkGroupSyncV2CatchupResult> runOnce() async {
    final prefs = _preferences ?? await SharedPreferences.getInstance();
    if (prefs.getBool(flagKey) == true) {
      return const PkGroupSyncV2CatchupResult(alreadyCompleted: true);
    }

    try {
      final settings = await _db.systemSettingsDao.getSettings();
      if (!settings.pkGroupSyncV2Enabled) {
        return const PkGroupSyncV2CatchupResult();
      }

      final groups = await _activePkGroupsForCatchup();
      final groupsById = {for (final group in groups) group.id: group};
      var groupsEmitted = 0;
      var entriesEmitted = 0;

      for (final group in groups) {
        await _recordGroupUpdate(
          table: _groupTable,
          entityId: _groupEntityId(group),
          fields: _groupFields(group),
        );
        groupsEmitted++;
      }

      if (groupsById.isNotEmpty) {
        final entries = await _activeEntriesForGroups(groupsById.keys);
        final membersById = await _membersById(
          entries.map((entry) => entry.memberId),
        );
        for (final entry in entries) {
          final group = groupsById[entry.groupId];
          if (group == null) continue;
          final member = membersById[entry.memberId];
          if (!_canEmitPkEntry(entry, group: group, member: member)) continue;
          await _recordEntryCreate(
            table: _entryTable,
            entityId: _entryEntityId(entry, group: group, member: member),
            fields: _entryFields(entry, group: group, member: member),
          );
          entriesEmitted++;
        }
      }

      await prefs.setBool(flagKey, true);
      return PkGroupSyncV2CatchupResult(
        groupsEmitted: groupsEmitted,
        entriesEmitted: entriesEmitted,
      );
    } catch (error) {
      debugPrint('[PK_GROUP_SYNC_V2] catch-up emit failed: $error');
      return PkGroupSyncV2CatchupResult(error: error.toString());
    }
  }

  Future<List<MemberGroupRow>> _activePkGroupsForCatchup() {
    return (_db.select(_db.memberGroups)..where(
          (group) =>
              group.isDeleted.equals(false) &
              group.syncSuppressed.equals(false) &
              group.pluralkitUuid.isNotNull() &
              group.pluralkitUuid.equals('').not(),
        ))
        .get();
  }

  Future<List<MemberGroupEntryRow>> _activeEntriesForGroups(
    Iterable<String> groupIds,
  ) async {
    final ids = groupIds.toSet().toList(growable: false);
    final entries = <MemberGroupEntryRow>[];
    for (var start = 0; start < ids.length; start += _lookupBatchSize) {
      final end = start + _lookupBatchSize > ids.length
          ? ids.length
          : start + _lookupBatchSize;
      final batch = ids.sublist(start, end);
      entries.addAll(
        await (_db.select(_db.memberGroupEntries)..where(
              (entry) =>
                  entry.isDeleted.equals(false) & entry.groupId.isIn(batch),
            ))
            .get(),
      );
    }
    return entries;
  }

  Future<Map<String, Member>> _membersById(Iterable<String> memberIds) async {
    final ids = memberIds.toSet().toList(growable: false);
    final membersById = <String, Member>{};
    for (var start = 0; start < ids.length; start += _lookupBatchSize) {
      final end = start + _lookupBatchSize > ids.length
          ? ids.length
          : start + _lookupBatchSize;
      final batch = ids.sublist(start, end);
      final members = await (_db.select(
        _db.members,
      )..where((m) => m.id.isIn(batch))).get();
      for (final member in members) {
        membersById[member.id] = member;
      }
    }
    return membersById;
  }

  static String _groupEntityId(MemberGroupRow group) {
    final pkUuid = group.pluralkitUuid;
    if (pkUuid != null && pkUuid.isNotEmpty) {
      return 'pk-group:$pkUuid';
    }
    return group.id;
  }

  static bool _canEmitPkEntry(
    MemberGroupEntryRow entry, {
    required MemberGroupRow group,
    required Member? member,
  }) {
    final pkGroupUuid = (entry.pkGroupUuid ?? group.pluralkitUuid ?? '').trim();
    if (pkGroupUuid.isEmpty) return true;

    final pkMemberUuid = (entry.pkMemberUuid ?? member?.pluralkitUuid ?? '')
        .trim();
    return pkMemberUuid.isNotEmpty;
  }

  static String _entryEntityId(
    MemberGroupEntryRow entry, {
    required MemberGroupRow group,
    required Member? member,
  }) {
    final pkGroupUuid = (entry.pkGroupUuid ?? group.pluralkitUuid ?? '').trim();
    final pkMemberUuid = (entry.pkMemberUuid ?? member?.pluralkitUuid ?? '')
        .trim();
    if (pkGroupUuid.isEmpty || pkMemberUuid.isEmpty) return entry.id;

    final digest = sha256.convert(
      utf8.encode('$pkGroupUuid\u0000$pkMemberUuid'),
    );
    return digest.toString().substring(0, 16);
  }

  /// Visible-for-testing: builds the group field map this service emits to the
  /// Rust sync engine. Exposed so a regression test can pin every emitted
  /// DateTime as Z-suffixed UTC.
  @visibleForTesting
  static Map<String, dynamic> debugGroupFields(MemberGroupRow row) =>
      _groupFields(row);

  static Map<String, dynamic> _groupFields(MemberGroupRow row) {
    return {
      'name': row.name,
      'description': row.description,
      'color_hex': row.colorHex,
      'emoji': row.emoji,
      'display_order': row.displayOrder,
      'parent_group_id': row.parentGroupId,
      'group_type': row.groupType,
      'filter_rules': row.filterRules,
      'created_at': _toSyncUtc(row.createdAt),
      'pluralkit_id': row.pluralkitId,
      'pluralkit_uuid': row.pluralkitUuid,
      'last_seen_from_pk_at': _toSyncUtcOrNull(row.lastSeenFromPkAt),
      'is_deleted': row.isDeleted,
    };
  }

  static Map<String, dynamic> _entryFields(
    MemberGroupEntryRow entry, {
    required MemberGroupRow group,
    required Member? member,
  }) {
    final pkGroupUuid = entry.pkGroupUuid ?? group.pluralkitUuid;
    final pkMemberUuid = entry.pkMemberUuid ?? member?.pluralkitUuid;
    return {
      'group_id': entry.groupId,
      'member_id': entry.memberId,
      if ((pkGroupUuid ?? '').isNotEmpty) 'pk_group_uuid': pkGroupUuid,
      if ((pkMemberUuid ?? '').isNotEmpty) 'pk_member_uuid': pkMemberUuid,
      'is_deleted': entry.isDeleted,
    };
  }
}

class PkGroupSyncV2CatchupResult {
  const PkGroupSyncV2CatchupResult({
    this.groupsEmitted = 0,
    this.entriesEmitted = 0,
    this.alreadyCompleted = false,
    this.error,
  });

  final int groupsEmitted;
  final int entriesEmitted;
  final bool alreadyCompleted;
  final String? error;

  bool get succeeded => error == null;
}

/// Normalizes a DateTime to UTC ISO-8601 (Z-suffixed) for sync wire emission.
///
/// Local DateTimes serialize with no offset/Z, so a peer in a different
/// timezone would parse the value as their own local time and shift the
/// absolute moment by the timezone delta on every sync. Mirrors the
/// `_dateTimeToSyncString` helper in `core/sync/drift_sync_adapter.dart`.
String _toSyncUtc(DateTime dt) => dt.toUtc().toIso8601String();

String? _toSyncUtcOrNull(DateTime? dt) => dt?.toUtc().toIso8601String();
