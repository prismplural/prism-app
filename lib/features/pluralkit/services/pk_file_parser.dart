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

  const PkFileExport({
    required this.system,
    required this.members,
    required this.groups,
    required this.switches,
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

/// Parse a `pk;export` JSON string into structured data.
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

  final groups = <PKGroup>[];
  final rawGroups = decoded['groups'];
  if (rawGroups is List) {
    for (final entry in rawGroups) {
      if (entry is Map<String, dynamic>) {
        try {
          groups.add(PKGroup.fromJson(entry));
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
  );
}
