import 'dart:convert';
import 'dart:typed_data';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sharing/share_scope.dart';

enum PendingSharingTrustDecision {
  accept,
  warnKeyChange,
  blockKeyChange,
  error;

  static PendingSharingTrustDecision parse(String raw) {
    return switch (raw) {
      'accept' => PendingSharingTrustDecision.accept,
      'warn_key_change' => PendingSharingTrustDecision.warnKeyChange,
      'block_key_change' => PendingSharingTrustDecision.blockKeyChange,
      _ => PendingSharingTrustDecision.error,
    };
  }

  String get storageValue => switch (this) {
    PendingSharingTrustDecision.accept => 'accept',
    PendingSharingTrustDecision.warnKeyChange => 'warn_key_change',
    PendingSharingTrustDecision.blockKeyChange => 'block_key_change',
    PendingSharingTrustDecision.error => 'error',
  };

  String get title => switch (this) {
    PendingSharingTrustDecision.accept => 'Ready to accept',
    PendingSharingTrustDecision.warnKeyChange => 'Security keys changed',
    PendingSharingTrustDecision.blockKeyChange => 'Verified keys changed',
    PendingSharingTrustDecision.error => 'Processing failed',
  };
}

class PendingSharingRequest {
  const PendingSharingRequest({
    required this.initId,
    required this.senderSharingId,
    required this.displayName,
    required this.offeredScopes,
    required this.trustDecision,
    required this.receivedAt,
    this.senderIdentity,
    this.pairwiseSecret,
    this.fingerprint,
    this.errorMessage,
    this.isResolved = false,
    this.resolvedAt,
  });

  final String initId;
  final String senderSharingId;
  final String displayName;
  final List<ShareScope> offeredScopes;
  final PendingSharingTrustDecision trustDecision;
  final Uint8List? senderIdentity;
  final Uint8List? pairwiseSecret;
  final String? fingerprint;
  final String? errorMessage;
  final DateTime receivedAt;
  final bool isResolved;
  final DateTime? resolvedAt;

  bool get canAccept =>
      !isResolved &&
      trustDecision != PendingSharingTrustDecision.blockKeyChange &&
      pairwiseSecret != null &&
      senderIdentity != null &&
      errorMessage == null;

  bool get requiresAttention =>
      trustDecision == PendingSharingTrustDecision.warnKeyChange ||
      trustDecision == PendingSharingTrustDecision.blockKeyChange ||
      errorMessage != null;

  factory PendingSharingRequest.fromRow(SharingRequestRow row) {
    final offeredScopes = _decodeScopes(row.offeredScopes);
    return PendingSharingRequest(
      initId: row.initId,
      senderSharingId: row.senderSharingId,
      displayName: row.displayName,
      offeredScopes: offeredScopes,
      trustDecision: PendingSharingTrustDecision.parse(row.trustDecision),
      senderIdentity: row.senderIdentity != null
          ? Uint8List.fromList(row.senderIdentity!)
          : null,
      pairwiseSecret: row.pairwiseSecret != null
          ? Uint8List.fromList(row.pairwiseSecret!)
          : null,
      fingerprint: row.fingerprint,
      errorMessage: row.errorMessage,
      receivedAt: row.receivedAt,
      isResolved: row.isResolved,
      resolvedAt: row.resolvedAt,
    );
  }

  static List<ShareScope> _decodeScopes(String raw) {
    try {
      final decoded = (jsonDecode(raw) as List).cast<String>();
      final scopes = <ShareScope>[];
      for (final value in decoded) {
        for (final scope in ShareScope.values) {
          if (scope.name == value) {
            scopes.add(scope);
            break;
          }
        }
      }
      return scopes;
    } catch (_) {
      return const [];
    }
  }
}
