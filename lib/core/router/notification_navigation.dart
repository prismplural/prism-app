import 'dart:convert';

/// Untrusted notification data can name a target, never a route or record.
/// Fingerprints are validated for legacy compatibility, then discarded.
class NotificationIntent {
  const NotificationIntent.fronting() : reminderId = null;
  const NotificationIntent.reminder(this.reminderId);

  final String? reminderId;
  bool get isFronting => reminderId == null;

  static const maxPayloadLength = 8192;
  static final _id = RegExp(r'^[a-zA-Z0-9_-]{1,128}$');

  static bool _validId(String id) =>
      _id.firstMatch(id)?.end == id.length && id.isNotEmpty;

  static NotificationIntent? parse(String? payload) {
    if (payload == null || payload.length > maxPayloadLength) return null;
    if (payload == 'prism:fronting:v1') {
      return const NotificationIntent.fronting();
    }
    for (final prefix in [
      'prism:reminder:scheduled:',
      'prism:reminder:immediate:',
    ]) {
      if (payload.startsWith(prefix)) {
        final id = payload.substring(prefix.length);
        return _validId(id) ? NotificationIntent.reminder(id) : null;
      }
    }
    const delayed = 'prism:reminder:front-change-delayed:';
    if (!payload.startsWith(delayed)) return null;
    final separator = payload.indexOf(':', delayed.length);
    if (separator < 0) return null;
    final id = payload.substring(delayed.length, separator);
    if (!_validId(id)) return null;
    try {
      final fingerprint = jsonDecode(payload.substring(separator + 1));
      if (fingerprint is! List ||
          fingerprint.length != 4 ||
          fingerprint[0] is! String ||
          fingerprint[1] is! String ||
          (fingerprint[2] != null && fingerprint[2] is! int) ||
          (fingerprint[3] != null && fingerprint[3] is! String)) {
        return null;
      }
    } on FormatException {
      return null;
    }
    return NotificationIntent.reminder(id);
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationIntent && reminderId == other.reminderId;

  @override
  int get hashCode => reminderId.hashCode;
}

/// One latest distinct target. No raw payload, DB object or route is retained.
/// The authorized shell must recheck its own gates after each await, then
/// [complete] the claim synchronously immediately before an allowlisted go().
class PendingNotificationIntents {
  NotificationIntent? _pending;
  int _generation = 0;
  int? _claimed;
  int _claimSequence = 0;

  NotificationIntent? get pending => _pending;

  bool receive(String? payload) {
    final intent = NotificationIntent.parse(payload);
    if (intent == null || intent == _pending) return false;
    _pending = intent;
    _generation++;
    _claimed = null;
    return true;
  }

  NotificationIntentClaim? claim() {
    final intent = _pending;
    if (intent == null || _claimed != null) return null;
    final token = ++_claimSequence;
    _claimed = token;
    return NotificationIntentClaim._(intent, _generation, token);
  }

  bool isCurrent(NotificationIntentClaim claim) =>
      claim._generation == _generation &&
      _claimed == claim._token &&
      claim.intent == _pending;

  bool complete(NotificationIntentClaim claim) {
    if (!isCurrent(claim)) return false;
    clear();
    return true;
  }

  /// A relock or suspend defers rather than discards the protected target.
  void release(NotificationIntentClaim claim) {
    if (isCurrent(claim)) _claimed = null;
  }

  /// Reset/account replacement invalidates pending and in-flight claims.
  void clear() {
    _generation++;
    _claimed = null;
    _pending = null;
  }
}

class NotificationIntentClaim {
  const NotificationIntentClaim._(this.intent, this._generation, this._token);
  final NotificationIntent intent;
  final int _generation;
  final int _token;
}
