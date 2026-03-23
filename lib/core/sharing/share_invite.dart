import 'dart:convert';

/// An invite payload that can be shared via QR code or link.
///
/// Contains the sender's X25519 public key and a random link ID
/// for the relay to route the key exchange.
class ShareInvite {
  final String linkId;
  final String publicKeyHex;
  final String displayName;
  final DateTime createdAt;
  final DateTime expiresAt;

  ShareInvite({
    required this.linkId,
    required this.publicKeyHex,
    required this.displayName,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Whether the invite has passed its expiry time.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Encode as a shareable JSON string (for QR code or deep link).
  String toShareString() => jsonEncode({
        'linkId': linkId,
        'pubKey': publicKeyHex,
        'name': displayName,
        'exp': expiresAt.millisecondsSinceEpoch,
      });

  /// Decode a share string back into a [ShareInvite].
  factory ShareInvite.fromShareString(String s) {
    final map = jsonDecode(s) as Map<String, dynamic>;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      map['exp'] as int,
    );
    return ShareInvite(
      linkId: map['linkId'] as String,
      publicKeyHex: map['pubKey'] as String,
      displayName: map['name'] as String,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
    );
  }
}
