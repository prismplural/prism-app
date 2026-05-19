/// Typed model + persistence for "which secure-storage slots are unreadable
/// right now?".
///
/// Each slot — the app DB key, the sync DB key, sync credentials, and the
/// PIN — has a [SlotState]. The aggregate [KeychainDegradedState] is
/// persisted as a single JSON value in [SharedPreferences] so the answer
/// survives restarts and is the single source of truth for the in-app
/// degraded banner copy.
///
/// ## Parsing tolerance
///
/// Future-proofing is encoded in [KeychainDegradedState.fromJson]:
///
/// 1. **Unknown enum strings → [SlotState.degraded].** A future version may
///    add new states (e.g. `locked`). If an older build reads such a value,
///    treating it as `ok` would silently hide a problem; `degraded` is the
///    safer default.
/// 2. **Missing fields default to `ok` ONLY when the field was introduced
///    after the saved schema's `schemaVersion`.** Fields existing at the
///    saved version must parse from the saved value or throw
///    [FormatException] — that's a corrupt save, not a forward-compat
///    case. The per-field introduction map [_fieldIntroductionVersion]
///    makes this explicit and reviewable.
/// 3. **Saved `schemaVersion` higher than [currentSchemaVersion]** (older
///    app reading newer save state): still parse best-effort. Ignore extra
///    fields. Do NOT throw — the user just downgraded; their data
///    shouldn't be deleted.
///
/// ## Not wired up yet
///
/// §8 of `docs/0.9.2-secure-storage-remediation.md` covers the model and
/// service only. Wiring slot transitions into the boot path, the recovery
/// UI, and the banner lives in §4/§5/§6/§7.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// State of an individual secure-storage slot.
///
/// `ok`         — slot read cleanly and the value (if any) is usable.
/// `unreadable` — read failed or returned corrupt data; the slot must be
///                recovered (typically by re-pairing or a fresh setup).
/// `degraded`   — partial failure (e.g. some fields of a multi-field slot
///                missing). Currently only meaningful for
///                [KeychainDegradedState.syncCredentials].
enum SlotState { ok, unreadable, degraded }

/// SharedPreferences key for the persisted JSON blob.
const String _kKeychainDegradedStateKey = 'prism.keychain.degraded_state';

/// Current on-disk schema version. Bump when adding a slot field — and add
/// the new field to [_fieldIntroductionVersion] with this same version
/// number so older saves load with the new field defaulted to `ok`.
const int currentSchemaVersion = 1;

/// Maps each slot field name to the [currentSchemaVersion] at which it
/// was introduced. Used by [KeychainDegradedState.fromJson] to decide
/// whether a missing field is "corrupt save" or "older save, new field".
const Map<String, int> _fieldIntroductionVersion = <String, int>{
  'appDbKey': 1,
  'syncKey': 1,
  'syncCredentials': 1,
  'pin': 1,
};

/// All known slot field names. Used by [KeychainDegradedStateService.updateSlot]
/// to reject unknown names with a log + no-op.
const Set<String> _knownSlotNames = <String>{
  'appDbKey',
  'syncKey',
  'syncCredentials',
  'pin',
};

@immutable
class KeychainDegradedState {
  const KeychainDegradedState({
    required this.appDbKey,
    required this.syncKey,
    required this.syncCredentials,
    required this.pin,
    required this.firstObservedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// All-healthy state. Used as the default when no save exists and the
  /// recovery state after a successful re-pair / fresh install.
  const KeychainDegradedState.healthy()
      : appDbKey = SlotState.ok,
        syncKey = SlotState.ok,
        syncCredentials = SlotState.ok,
        pin = SlotState.ok,
        firstObservedAt = null,
        schemaVersion = currentSchemaVersion;

  final SlotState appDbKey;
  final SlotState syncKey;
  final SlotState syncCredentials;
  final SlotState pin;

  /// When did the state first leave fully-healthy? `null` when healthy.
  /// Cleared on a full transition back to healthy. The §later banner
  /// surfaces voluntary-reset copy once this is older than 7 days.
  final DateTime? firstObservedAt;

  /// Schema version of the source data. Newly-constructed instances use
  /// [currentSchemaVersion]; instances parsed from JSON preserve whatever
  /// the saved value was (so [toJson] round-trips it).
  final int schemaVersion;

  /// True iff every slot is `ok`.
  bool get isHealthy =>
      appDbKey == SlotState.ok &&
      syncKey == SlotState.ok &&
      syncCredentials == SlotState.ok &&
      pin == SlotState.ok;

  /// True iff any slot is specifically `unreadable` (not just `degraded`).
  bool get hasAnyUnreadable =>
      appDbKey == SlotState.unreadable ||
      syncKey == SlotState.unreadable ||
      syncCredentials == SlotState.unreadable ||
      pin == SlotState.unreadable;

  /// Names of slots whose state is not `ok`.
  Set<String> get unreadableSlotNames {
    final names = <String>{};
    if (appDbKey != SlotState.ok) names.add('appDbKey');
    if (syncKey != SlotState.ok) names.add('syncKey');
    if (syncCredentials != SlotState.ok) names.add('syncCredentials');
    if (pin != SlotState.ok) names.add('pin');
    return names;
  }

  KeychainDegradedState copyWith({
    SlotState? appDbKey,
    SlotState? syncKey,
    SlotState? syncCredentials,
    SlotState? pin,
    Object? firstObservedAt = _sentinel,
    int? schemaVersion,
  }) {
    return KeychainDegradedState(
      appDbKey: appDbKey ?? this.appDbKey,
      syncKey: syncKey ?? this.syncKey,
      syncCredentials: syncCredentials ?? this.syncCredentials,
      pin: pin ?? this.pin,
      firstObservedAt: identical(firstObservedAt, _sentinel)
          ? this.firstObservedAt
          : firstObservedAt as DateTime?,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'appDbKey': _encodeSlot(appDbKey),
        'syncKey': _encodeSlot(syncKey),
        'syncCredentials': _encodeSlot(syncCredentials),
        'pin': _encodeSlot(pin),
        'firstObservedAt': firstObservedAt?.toIso8601String(),
      };

  /// Parse from JSON with the tolerance rules documented at the top of
  /// this library. Throws [FormatException] when a field that existed at
  /// the saved [schemaVersion] is missing or null — that's a corrupt
  /// save, not a forward-compat case.
  factory KeychainDegradedState.fromJson(Map<String, dynamic> json) {
    final rawVersion = json['schemaVersion'];
    if (rawVersion is! int) {
      throw const FormatException(
        'KeychainDegradedState: missing or non-int schemaVersion',
      );
    }
    final savedVersion = rawVersion;

    SlotState readSlot(String fieldName) {
      final raw = json[fieldName];
      if (raw == null) {
        // Field is missing. Allowed only when the field was introduced
        // AFTER the saved schema's version — then it defaults to ok.
        final introducedAt = _fieldIntroductionVersion[fieldName] ?? 1;
        if (introducedAt > savedVersion) {
          return SlotState.ok;
        }
        throw FormatException(
          'KeychainDegradedState: required field "$fieldName" missing '
          'at saved schemaVersion $savedVersion',
        );
      }
      if (raw is! String) {
        throw FormatException(
          'KeychainDegradedState: field "$fieldName" must be a String, '
          'got ${raw.runtimeType}',
        );
      }
      return _decodeSlot(raw);
    }

    DateTime? readFirstObservedAt() {
      final raw = json['firstObservedAt'];
      if (raw == null) return null;
      if (raw is! String) {
        throw FormatException(
          'KeychainDegradedState: firstObservedAt must be a String or '
          'null, got ${raw.runtimeType}',
        );
      }
      return DateTime.parse(raw);
    }

    return KeychainDegradedState(
      appDbKey: readSlot('appDbKey'),
      syncKey: readSlot('syncKey'),
      syncCredentials: readSlot('syncCredentials'),
      pin: readSlot('pin'),
      firstObservedAt: readFirstObservedAt(),
      schemaVersion: savedVersion,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeychainDegradedState &&
        other.appDbKey == appDbKey &&
        other.syncKey == syncKey &&
        other.syncCredentials == syncCredentials &&
        other.pin == pin &&
        other.firstObservedAt == firstObservedAt &&
        other.schemaVersion == schemaVersion;
  }

  @override
  int get hashCode => Object.hash(
        appDbKey,
        syncKey,
        syncCredentials,
        pin,
        firstObservedAt,
        schemaVersion,
      );

  @override
  String toString() {
    return 'KeychainDegradedState('
        'appDbKey: ${appDbKey.name}, '
        'syncKey: ${syncKey.name}, '
        'syncCredentials: ${syncCredentials.name}, '
        'pin: ${pin.name}, '
        'firstObservedAt: $firstObservedAt, '
        'schemaVersion: $schemaVersion)';
  }
}

/// Distinguishes "caller passed null explicitly" from "caller omitted the
/// argument" in [KeychainDegradedState.copyWith].
const Object _sentinel = Object();

String _encodeSlot(SlotState state) => state.name;

/// Decode a slot string, tolerating unknown values by mapping them to
/// [SlotState.degraded] (the safer default — see top-of-file docs).
SlotState _decodeSlot(String raw) {
  for (final value in SlotState.values) {
    if (value.name == raw) return value;
  }
  return SlotState.degraded;
}

/// Service: read / write / per-slot update.
///
/// All transitions log via `debugPrint` in a readable JSON form so the
/// `[KEYCHAIN_STATE]` lines can be greppedfrom user-submitted crash logs.
class KeychainDegradedStateService {
  KeychainDegradedStateService({SharedPreferences? prefs}) : _prefs = prefs;

  final SharedPreferences? _prefs;

  Future<SharedPreferences> _resolvePrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  /// Returns the persisted state, or [KeychainDegradedState.healthy] if
  /// no save exists. Parse failures are logged and recovered to healthy —
  /// we never crash the app on a corrupt save.
  Future<KeychainDegradedState> read() async {
    final prefs = await _resolvePrefs();
    final raw = prefs.getString(_kKeychainDegradedStateKey);
    if (raw == null || raw.isEmpty) {
      return const KeychainDegradedState.healthy();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'KeychainDegradedState: saved value is not a JSON object',
        );
      }
      return KeychainDegradedState.fromJson(decoded);
    } catch (e) {
      debugPrint(
        '[KEYCHAIN_STATE] failed to parse saved state, returning healthy: $e',
      );
      return const KeychainDegradedState.healthy();
    }
  }

  /// Overwrite the persisted state.
  Future<void> write(KeychainDegradedState state) async {
    final prefs = await _resolvePrefs();
    final encoded = jsonEncode(state.toJson());
    await prefs.setString(_kKeychainDegradedStateKey, encoded);
  }

  /// Read, set [slotName] to [newState], log + write.
  ///
  /// Manages [KeychainDegradedState.firstObservedAt]:
  /// - healthy → not-healthy: stamps `firstObservedAt = DateTime.now()`
  /// - not-healthy → healthy: clears `firstObservedAt = null`
  /// - any other transition: leaves it unchanged
  ///
  /// Unknown [slotName] → log + no-op (no throw — defensive against
  /// future callers that mistype).
  Future<void> updateSlot(String slotName, SlotState newState) async {
    if (!_knownSlotNames.contains(slotName)) {
      debugPrint(
        '[KEYCHAIN_STATE] updateSlot: unknown slot "$slotName" — ignoring',
      );
      return;
    }
    final current = await read();
    final withSlot = _withSlot(current, slotName, newState);
    if (withSlot == current) {
      // No-op transition — don't churn SharedPreferences or the log.
      return;
    }

    DateTime? nextFirstObserved;
    if (current.isHealthy && !withSlot.isHealthy) {
      nextFirstObserved = DateTime.now();
    } else if (!current.isHealthy && withSlot.isHealthy) {
      nextFirstObserved = null;
    } else {
      nextFirstObserved = current.firstObservedAt;
    }

    final next = withSlot.copyWith(firstObservedAt: nextFirstObserved);
    debugPrint(
      '[KEYCHAIN_STATE] transition: '
      '${jsonEncode(current.toJson())} -> ${jsonEncode(next.toJson())}',
    );
    await write(next);
  }

  KeychainDegradedState _withSlot(
    KeychainDegradedState state,
    String slotName,
    SlotState newState,
  ) {
    switch (slotName) {
      case 'appDbKey':
        return state.copyWith(appDbKey: newState);
      case 'syncKey':
        return state.copyWith(syncKey: newState);
      case 'syncCredentials':
        return state.copyWith(syncCredentials: newState);
      case 'pin':
        return state.copyWith(pin: newState);
    }
    // Unreachable: callers pre-check via [_knownSlotNames].
    return state;
  }
}

/// Pure derivation of the user-facing banner string from a state.
///
/// This is the SINGLE source of truth for degraded-banner copy. UI code
/// MUST call this rather than re-deriving from raw [SlotState]s.
///
/// Returns `null` when the banner should be hidden.
///
/// Branches (in priority order):
/// 1. Healthy → null.
/// 2. Multiple slots unreadable → "see Settings for recovery options".
/// 3. `appDbKey == unreadable` → defense-in-depth message. This case is
///    normally handled by the §6/§7 full-screen recovery flow; if the
///    banner ever sees it, something upstream missed it.
/// 4. `syncKey == unreadable` → re-pair message.
/// 5. `syncCredentials != ok` → re-pair message (covers `degraded` too).
/// 6. `pin == unreadable` → set-new-PIN message.
String? deriveDegradedBannerMessage(KeychainDegradedState state) {
  if (state.isHealthy) return null;

  // Count slots that aren't `ok`. Multi-slot wins.
  final affected = state.unreadableSlotNames;
  if (affected.length > 1) {
    return 'Multiple keychain slots unreadable — see Settings for recovery '
        'options';
  }

  // Defense in depth — the app DB key case should be a full-screen
  // recovery flow, not a banner. Return a clearly-distinct message so
  // it's diagnosable in logs if we ever see it here.
  if (state.appDbKey == SlotState.unreadable) {
    return 'Local data unlock failed — see recovery options';
  }
  if (state.syncKey == SlotState.unreadable) {
    return 'Sync data unlock failed — re-pair to resume sync';
  }
  if (state.syncCredentials != SlotState.ok) {
    return 'Sync credentials unreadable — re-pair to resume sync';
  }
  if (state.pin == SlotState.unreadable) {
    return 'PIN lock data lost — set a new PIN in Settings';
  }
  return null;
}

/// Riverpod provider for the service.
///
/// Constructs the service lazily without injecting a [SharedPreferences]
/// instance — the service resolves one on first call via
/// `SharedPreferences.getInstance()`. Tests inject directly via the
/// constructor instead of overriding this provider.
final keychainDegradedStateProvider =
    Provider<KeychainDegradedStateService>((ref) {
  return KeychainDegradedStateService();
});
