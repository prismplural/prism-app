import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A single local Prism member that is not linked to PluralKit yet and is a
/// candidate for the one-time push flow surfaced by the
/// "local-only members" notice banner.
class PkUnpushedMemberRef {
  /// Local Prism member id.
  final String memberId;
  final String memberName;
  final String? displayName;

  /// Locally-stored avatar bytes. Local-side equivalent of
  /// [PkUnmappedFronterRef.avatarUrl]; the member has never been to PK so we
  /// only have the cached image bytes from the Prism row.
  final Uint8List? avatarImageData;

  const PkUnpushedMemberRef({
    required this.memberId,
    required this.memberName,
    this.displayName,
    this.avatarImageData,
  });

  String get label {
    final display = displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    final base = memberName.trim();
    if (base.isNotEmpty) return base;
    return memberId;
  }

  PkUnpushedMemberRef copyWith({
    String? memberId,
    String? memberName,
    String? displayName,
    Uint8List? avatarImageData,
  }) {
    return PkUnpushedMemberRef(
      memberId: memberId ?? this.memberId,
      memberName: memberName ?? this.memberName,
      displayName: displayName ?? this.displayName,
      avatarImageData: avatarImageData ?? this.avatarImageData,
    );
  }

  @override
  String toString() => 'PkUnpushedMemberRef(redacted)';
}

/// Notice describing the cohort of local-only members that the user could
/// push to PluralKit. Identity is the set of member IDs in [refs] — the
/// dismissal hash is over that set, so adding/removing a member resurfaces
/// the banner.
class PkUnpushedMembersNotice {
  final List<PkUnpushedMemberRef> refs;

  const PkUnpushedMembersNotice({required this.refs});

  Set<String> get memberIds => {for (final ref in refs) ref.memberId};

  String get dismissalKey =>
      pkUnpushedMembersDismissalKey(memberIds: memberIds);

  @override
  String toString() => 'PkUnpushedMembersNotice(redacted)';
}

String pkUnpushedMembersDismissalKey({required Set<String> memberIds}) {
  final ids = memberIds.toList()..sort();
  final canonical = jsonEncode(ids);
  return sha256.convert(utf8.encode(canonical)).toString();
}
