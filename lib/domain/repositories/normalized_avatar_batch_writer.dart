import 'dart:typed_data';

abstract interface class NormalizedAvatarBatchWriter {
  Future<NormalizedAvatarBatchResult> applyNormalizedAvatarBatch(
    Map<String, Uint8List> bytesByMemberId,
  );
}

final class NormalizedAvatarBatchResult {
  NormalizedAvatarBatchResult({
    required this.requested,
    required Iterable<String> updatedMemberIds,
    required Iterable<String> unchangedMemberIds,
    required Iterable<String> missingOrDeletedMemberIds,
  }) : updatedMemberIds = Set.unmodifiable(updatedMemberIds),
       unchangedMemberIds = Set.unmodifiable(unchangedMemberIds),
       missingOrDeletedMemberIds = Set.unmodifiable(missingOrDeletedMemberIds);

  final int requested;
  final Set<String> updatedMemberIds;
  final Set<String> unchangedMemberIds;
  final Set<String> missingOrDeletedMemberIds;
}
