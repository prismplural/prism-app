import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/member.dart';

/// Batch-loads members by ID. Key is sorted, comma-joined IDs for cache stability.
///
/// Riverpod `.family` uses `==`/`hashCode` on the family parameter. Dart
/// `Set<String>` has reference equality, so we use a sorted comma-joined
/// String key instead.
final membersByIdsProvider = StreamProvider.autoDispose
    .family<Map<String, Member>, String>((ref, idsKey) {
      if (idsKey.isEmpty) return Stream.value(<String, Member>{});
      final ids = idsKey.split(',');
      final repo = ref.watch(memberRepositoryProvider);
      return repo
          .watchMembersByIds(ids)
          .map(
            (members) => {
              for (final m in members)
                if (!m.isDeleted) m.id: m,
            },
          );
    });

/// Batch-loads list-shaped members by ID for history/list/timeline surfaces.
///
/// These rows intentionally omit long bios and image blobs. Visible avatar
/// widgets hydrate their own blobs by member id, keeping the history/timeline
/// stream payload small on large systems.
final membersByIdsListProvider = StreamProvider.autoDispose
    .family<Map<String, Member>, String>((ref, idsKey) {
      if (idsKey.isEmpty) return Stream.value(<String, Member>{});
      final ids = idsKey.split(',');
      try {
        final repo = ref.watch(memberRepositoryProvider);
        final stream = repo is DriftMemberRepository
            ? repo.watchMembersByIdsForList(ids)
            : repo.watchMembersByIds(ids);
        return stream.map(_memberMap);
      } catch (_) {
        return _streamFromMemberMapAsync(
          ref.watch(membersByIdsProvider(idsKey)),
        );
      }
    });

/// Helper to create a stable cache key from member IDs.
String memberIdsKey(Iterable<String> ids) => (ids.toList()..sort()).join(',');

Map<String, Member> _memberMap(List<Member> members) {
  return {
    for (final m in members)
      if (!m.isDeleted) m.id: m,
  };
}

Stream<Map<String, Member>> _streamFromMemberMapAsync(
  AsyncValue<Map<String, Member>> async,
) {
  return async.when(
    data: Stream.value,
    loading: () => const Stream<Map<String, Member>>.empty(),
    error: Stream.error,
  );
}
