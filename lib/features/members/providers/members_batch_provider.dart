import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';

/// Batch-loads members by ID. Key is sorted, comma-joined IDs for cache stability.
///
/// Riverpod `.family` uses `==`/`hashCode` on the family parameter. Dart
/// `Set<String>` has reference equality, so we use a sorted comma-joined
/// String key instead.
final membersByIdsProvider =
    StreamProvider.autoDispose.family<Map<String, Member>, String>((ref, idsKey) {
  if (idsKey.isEmpty) return Stream.value(<String, Member>{});
  final ids = idsKey.split(',');
  final repo = ref.watch(memberRepositoryProvider);
  return repo
      .watchMembersByIds(ids)
      .map((members) => {for (final m in members) m.id: m});
});

/// Helper to create a stable cache key from member IDs.
String memberIdsKey(Iterable<String> ids) =>
    (ids.toList()..sort()).join(',');
