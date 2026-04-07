import 'dart:convert';

/// A Phase 4 sharing invite payload.
///
/// This is an out-of-band discovery token carrying the recipient's stable
/// `sharing_id`, plus an optional display name to make the sender-facing UI
/// friendlier. It does not contain public keys or ephemeral KEM material.
class ShareInvite {
  ShareInvite({
    required this.sharingId,
    this.displayName,
    required this.createdAt,
  });

  final String sharingId;
  final String? displayName;
  final DateTime createdAt;

  bool get isExpired => false;

  String toShareString() => jsonEncode({
    'version': 2,
    'sharingId': sharingId,
    if (displayName != null) 'name': displayName,
    'createdAt': createdAt.millisecondsSinceEpoch,
  });

  factory ShareInvite.fromShareString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invite payload must be a JSON object');
    }
    final sharingId = decoded['sharingId'];
    if (sharingId is! String || sharingId.isEmpty) {
      throw const FormatException('Invite payload is missing sharingId');
    }

    final createdAtMillis = decoded['createdAt'];
    return ShareInvite(
      sharingId: sharingId,
      displayName: decoded['name'] as String?,
      createdAt: createdAtMillis is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAtMillis)
          : DateTime.now(),
    );
  }
}
