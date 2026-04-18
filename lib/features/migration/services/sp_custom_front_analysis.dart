import 'package:prism_plurality/features/migration/services/sp_custom_front_disposition.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

/// Word-boundary, case-insensitive match for sleep-ish CF names. Matches
/// whole-word occurrences of sleep/asleep/sleeping/nap/napping so that
/// "Sleep", "Asleep", and "Nap" resolve to [CfDisposition.convertToSleep]
/// while "overslept" / "unsleep" / "napkin" do not.
final RegExp _sleepNameRegex =
    RegExp(r'\b(sleep|asleep|sleeping|nap|napping)\b', caseSensitive: false);

/// Count how each SP custom front is used across the parsed export.
///
/// Walks front history (primary + co-fronter) and automated timers
/// (`type == 1` targets). Returns a map keyed by SP CF id; CFs that don't
/// appear anywhere get a zero-filled entry.
Map<String, CfUsageStats> analyzeCfUsage(SpExportData data) {
  final primary = <String, int>{};
  final coFronter = <String, int>{};
  final timer = <String, int>{};

  for (final entry in data.frontHistory) {
    final id = entry.memberId;
    if (id != null && id.isNotEmpty && id != 'unknown') {
      primary[id] = (primary[id] ?? 0) + 1;
    }
    for (final cfId in entry.coFronters) {
      if (cfId.isEmpty) continue;
      coFronter[cfId] = (coFronter[cfId] ?? 0) + 1;
    }
  }

  for (final t in data.automatedTimers) {
    if (t.type == 1) {
      final id = t.targetId;
      if (id != null && id.isNotEmpty) {
        timer[id] = (timer[id] ?? 0) + 1;
      }
    }
  }

  final result = <String, CfUsageStats>{};
  final cfIds = <String>{for (final cf in data.customFronts) cf.id};
  // Seed every known CF so callers can rely on presence.
  for (final id in cfIds) {
    result[id] = CfUsageStats(
      asPrimary: primary[id] ?? 0,
      asCoFronter: coFronter[id] ?? 0,
      asTimerTarget: timer[id] ?? 0,
    );
  }
  // Include counts for ids that showed up in history/timers even if they're
  // not in the CF list (synthetic / deleted CFs). Callers may use these.
  for (final id in {...primary.keys, ...coFronter.keys, ...timer.keys}) {
    if (!result.containsKey(id)) {
      result[id] = CfUsageStats(
        asPrimary: primary[id] ?? 0,
        asCoFronter: coFronter[id] ?? 0,
        asTimerTarget: timer[id] ?? 0,
      );
    }
  }
  return result;
}

/// Pick a default disposition for each CF using the ordered rules from the
/// plan (§Smart defaults):
///
///   1. Zero usage everywhere → Skip.
///   2. Name matches sleep regex → Convert to sleep.
///   3. Co-fronter-only (never primary) → Merge as note.
///   4. Primary ≥ 50% of usage → Import as member.
///   5. Otherwise → Merge as note.
Map<String, CfSuggestion> suggestDefaults(
  List<SpCustomFront> cfs,
  Map<String, CfUsageStats> usage,
) {
  final result = <String, CfSuggestion>{};
  for (final cf in cfs) {
    final stats = usage[cf.id] ?? const CfUsageStats();

    // Rule 1: zero usage → skip.
    if (stats.total == 0) {
      result[cf.id] = const CfSuggestion(
        disposition: CfDisposition.skip,
        reason: 'Never used in front history or timers',
      );
      continue;
    }

    // Rule 2: sleep-ish name → convert to sleep.
    if (_sleepNameRegex.hasMatch(cf.name)) {
      result[cf.id] = const CfSuggestion(
        disposition: CfDisposition.convertToSleep,
        reason: 'Name matches sleep keywords',
      );
      continue;
    }

    // Rule 3: co-fronter-only.
    if (stats.asPrimary == 0 && stats.asCoFronter > 0) {
      result[cf.id] = const CfSuggestion(
        disposition: CfDisposition.mergeAsNote,
        reason: 'Only used as co-fronter',
      );
      continue;
    }

    // Rule 4: primary-heavy (≥ 50% of front-history usage).
    final frontHistoryTotal = stats.asPrimary + stats.asCoFronter;
    if (frontHistoryTotal > 0 &&
        stats.asPrimary * 2 >= frontHistoryTotal) {
      result[cf.id] = const CfSuggestion(
        disposition: CfDisposition.importAsMember,
        reason: 'Used mostly as primary fronter',
      );
      continue;
    }

    // Rule 5: default.
    result[cf.id] = const CfSuggestion(
      disposition: CfDisposition.mergeAsNote,
      reason: 'Mixed usage — safest to preserve as a note',
    );
  }
  return result;
}
