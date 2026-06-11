import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';

/// Parsed contents of a `pk;export` JSON file.
class PkFileExport {
  final PKSystem system;
  final List<PKMember> members;
  final List<PKGroup> groups;

  /// Switch entries from the export file. Export switches lack an `id` field
  /// (the API's `/switches` endpoint provides one, but `pk;export` doesn't),
  /// so we carry a lightweight shape separate from [PKSwitch].
  final List<PkFileSwitch> switches;

  /// Count of `groups[].members` references that could not be resolved to a
  /// UUID — a short ID that doesn't appear in this export's own `members[]`
  /// table (corrupted or hand-edited file). Those refs are dropped from the
  /// group. NOT yet surfaced in the import-summary UI — exposed here so a
  /// future summary can report honest shrinkage instead of silently losing
  /// members. See the parser contract on [parsePkExportFile].
  final int unresolvableGroupMemberRefs;

  const PkFileExport({
    required this.system,
    required this.members,
    required this.groups,
    required this.switches,
    this.unresolvableGroupMemberRefs = 0,
  });
}

/// A switch entry as it appears in a `pk;export` file — just timestamp +
/// fronter member short IDs.
class PkFileSwitch {
  final String? id;
  final DateTime timestamp;
  final List<String> memberIds;

  const PkFileSwitch({
    this.id,
    required this.timestamp,
    required this.memberIds,
  });
}

/// Summary returned from [PluralKitSyncService.importFromFile].
class PkFileImportResult {
  final String? systemName;
  final int membersImported;
  final int groupsImported;
  final int switchesCreated;
  final int switchesSkipped;

  const PkFileImportResult({
    required this.systemName,
    required this.membersImported,
    required this.groupsImported,
    required this.switchesCreated,
    required this.switchesSkipped,
  });
}

/// Summary returned from the hybrid `pk;export` + token fronting import.
class PkFileTokenFrontingImportResult {
  final String? systemName;
  final int membersImported;
  final int groupsImported;
  final bool canonicalizationSafe;
  final bool frontingImported;
  final int exactImportedCount;
  final int staleFileCount;
  final int ambiguousCount;
  final List<String> ambiguousKeys;
  final int fileOnlyCount;
  final int apiOnlyInRangeCount;
  final int apiOnlyOutsideRangeCount;
  final int apiSwitchesFetched;
  final int unmappedMemberReferences;
  final Map<int, String> apiSwitchIdsByFileIndex;

  const PkFileTokenFrontingImportResult({
    required this.systemName,
    required this.membersImported,
    required this.groupsImported,
    required this.canonicalizationSafe,
    required this.frontingImported,
    required this.exactImportedCount,
    required this.staleFileCount,
    required this.ambiguousCount,
    required this.ambiguousKeys,
    required this.fileOnlyCount,
    required this.apiOnlyInRangeCount,
    required this.apiOnlyOutsideRangeCount,
    required this.apiSwitchesFetched,
    required this.unmappedMemberReferences,
    required this.apiSwitchIdsByFileIndex,
  });
}

/// Raised when the file can't be parsed as a PK v2 export.
class PkFileParseException implements Exception {
  final String message;
  PkFileParseException(this.message);
  @override
  String toString() => 'PkFileParseException: $message';
}

/// Matches a canonical PluralKit UUID (`8-4-4-4-12` hex, dashed). Tolerates
/// upper- or lower-case hex. Used to tell a UUID apart from a short ID (hid)
/// in `groups[].members`.
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Matches a normalized PluralKit short ID (hid): 5–6 ASCII letters once
/// dashes are stripped and the value is lower-cased. PK exports emit lowercase,
/// dashless hids, but the API accepts uppercase/dashed forms, so we normalize
/// before matching to stay tolerant of hand-edited files.
final RegExp _normalizedHidPattern = RegExp(r'^[a-z]{5,6}$');

/// Normalize a PluralKit short ID for lookup: lowercase + strip dashes.
/// Returns null if the result isn't a plausible hid (5–6 alpha chars).
String? _normalizeHid(String raw) {
  final normalized = raw.toLowerCase().replaceAll('-', '').trim();
  if (!_normalizedHidPattern.hasMatch(normalized)) return null;
  return normalized;
}

/// Parse a `pk;export` JSON string into structured data.
///
/// **Identity contract:** the on-the-wire `pk;export` file references group
/// members by their PluralKit *short ID* (hid) in `groups[].members`, whereas
/// the live API (`GET /systems/@me/groups?with_members=true`) returns member
/// *UUIDs*. Downstream group reconciliation ([PkGroupsImporter]) is UUID-keyed
/// and runs removal-mode ("authoritative set") semantics, so feeding it hids
/// would resolve zero members and soft-delete every existing membership.
///
/// To make both inputs work, this parser **normalizes `groups[].memberIds` to
/// always be UUIDs**: each hid is translated through a hid→uuid map built from
/// the export's own `members[]` (every member entry carries both `id` and
/// `uuid`). Entries that are already UUID-shaped are kept verbatim (tolerates
/// the live-API shape and any future PK format change). A hid with no match in
/// `members[]` (corrupted / hand-edited file) is dropped and tallied on
/// [PkFileExport.unresolvableGroupMemberRefs].
///
/// `switches[].memberIds` are deliberately **left as hids** — switch matching
/// (`PkFrontingSwitchKey`) and the file-switch provenance id
/// (`_pkFileSwitchSourceId`) compare file hids against the API's short-ID
/// `members`, so translating them would break canonicalization.
///
/// Runs on a background isolate via [compute] — callers should await the
/// future but not expect ordering guarantees relative to other async work.
Future<PkFileExport> parsePkExportFile(String json) {
  return compute(_parseSync, json);
}

PkFileExport _parseSync(String raw) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (e) {
    throw PkFileParseException('File is not valid JSON: $e');
  }
  if (decoded is! Map<String, dynamic>) {
    throw PkFileParseException(
      'Expected a JSON object at the root of the export file.',
    );
  }

  // PluralKit exports carry `version: 2`. Fail loudly on unknown versions so
  // we don't silently misinterpret a different shape.
  final version = decoded['version'];
  if (version != 2) {
    throw PkFileParseException(
      'Unsupported export version ($version). This file was not produced by '
      '`pk;export` — or PluralKit changed its format.',
    );
  }

  final PKSystem system;
  try {
    system = PKSystem.fromJson(decoded);
  } catch (e) {
    throw PkFileParseException('Could not read the system block: $e');
  }

  final members = <PKMember>[];
  final rawMembers = decoded['members'];
  if (rawMembers is List) {
    for (final entry in rawMembers) {
      if (entry is Map<String, dynamic>) {
        try {
          members.add(PKMember.fromJson(entry));
        } catch (_) {
          // Skip individual malformed member entries rather than failing the
          // whole import — an old/partial export may still be mostly usable.
        }
      }
    }
  }

  // Build the hid→uuid translation table from the export's own member list.
  // Keys are normalized hids (lowercase, dashless) so a hand-edited file using
  // uppercase/dashed forms still resolves. Duplicate hids (impossible in a
  // genuine export — PK guarantees per-system uniqueness — but reachable in a
  // hand-corrupted file) resolve last-wins; empty refs are skipped without
  // counting as unresolvable.
  final hidToUuid = <String, String>{};
  for (final member in members) {
    final normalizedHid = _normalizeHid(member.id);
    if (normalizedHid != null) {
      hidToUuid[normalizedHid] = member.uuid;
    }
  }

  // Parse groups, then normalize `memberIds` to UUIDs. Real exports carry
  // hids here; the live API and the old fixtures carry UUIDs. See the
  // identity contract on [parsePkExportFile].
  final groups = <PKGroup>[];
  var unresolvableGroupMemberRefs = 0;
  final rawGroups = decoded['groups'];
  if (rawGroups is List) {
    for (final entry in rawGroups) {
      if (entry is Map<String, dynamic>) {
        try {
          final group = PKGroup.fromJson(entry);
          // `memberIds == null` means "unknown" (privacy / missing field) —
          // preserve that exactly; never translate or count it.
          final rawMemberIds = group.memberIds;
          if (rawMemberIds == null) {
            groups.add(group);
            continue;
          }
          final translated = <String>[];
          for (final ref in rawMemberIds) {
            final trimmed = ref.trim();
            if (trimmed.isEmpty) continue;
            if (_uuidPattern.hasMatch(trimmed)) {
              // Already a UUID — keep verbatim (live-API / old-fixture shape).
              translated.add(trimmed);
              continue;
            }
            final normalizedHid = _normalizeHid(trimmed);
            final uuid =
                normalizedHid == null ? null : hidToUuid[normalizedHid];
            if (uuid != null) {
              translated.add(uuid);
            } else {
              // Short ID with no member entry in this export — drop + count.
              unresolvableGroupMemberRefs++;
            }
          }
          groups.add(
            PKGroup(
              id: group.id,
              uuid: group.uuid,
              name: group.name,
              displayName: group.displayName,
              description: group.description,
              color: group.color,
              iconUrl: group.iconUrl,
              bannerUrl: group.bannerUrl,
              memberIds: translated,
            ),
          );
        } catch (_) {}
      }
    }
  }

  final switches = <PkFileSwitch>[];
  final rawSwitches = decoded['switches'];
  if (rawSwitches is List) {
    for (final entry in rawSwitches) {
      if (entry is! Map<String, dynamic>) continue;
      final ts = entry['timestamp'];
      if (ts is! String) continue;
      final DateTime parsed;
      try {
        parsed = DateTime.parse(ts);
      } catch (_) {
        continue;
      }
      final rawIds = entry['members'];
      final ids = <String>[];
      if (rawIds is List) {
        for (final id in rawIds) {
          if (id is String) ids.add(id);
        }
      }
      final rawId = entry['id'];
      switches.add(
        PkFileSwitch(
          id: rawId is String && rawId.trim().isNotEmpty ? rawId.trim() : null,
          timestamp: parsed,
          memberIds: ids,
        ),
      );
    }
  }

  return PkFileExport(
    system: system,
    members: members,
    groups: groups,
    switches: switches,
    unresolvableGroupMemberRefs: unresolvableGroupMemberRefs,
  );
}
