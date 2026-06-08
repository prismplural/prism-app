import 'package:flutter/foundation.dart';

/// One member-save timing breakdown, recorded for the awaited phases of
/// `_save()` and surfaced (copyable) in the Database Diagnostics screen.
///
/// Release-active by design — the cost is a few [Stopwatch] reads plus one
/// bounded-list insert per save — so on-device traces are available without a
/// console or a debug build.
@immutable
class AddMemberPerfEntry {
  const AddMemberPerfEntry({
    required this.isEditing,
    required this.totalMs,
    required this.customFieldCommitMs,
    required this.dirtyCustomFields,
    required this.memberWriteMs,
    required this.pkReloadMs,
    required this.avatarBytes,
    required this.headerBytes,
    required this.memberCount,
  });

  final bool isEditing;

  /// Total awaited wall-clock of `_save()`, excluding the PK push dialog.
  final int totalMs;

  /// Time inside `CustomFieldsEditorController.commit()`.
  final int customFieldCommitMs;

  /// Fields with staged edits at commit time (clean fields short-circuit).
  final int dirtyCustomFields;

  /// Time inside `createMember` / `updateMember`.
  final int memberWriteMs;

  /// Time inside the awaited PluralKit-settings gate (create path only).
  final int pkReloadMs;

  /// Raw avatar/header bytes, carried inline into the member op as base64.
  final int avatarBytes;
  final int headerBytes;

  /// Active member count at save time; `-1` if unavailable.
  final int memberCount;

  int get _otherMs =>
      (totalMs - customFieldCommitMs - memberWriteMs - pkReloadMs)
          .clamp(0, totalMs);

  /// One-line copyable summary.
  String format() {
    String kb(int bytes) => '${(bytes / 1024).toStringAsFixed(0)}KB';
    final op = isEditing ? 'edit' : 'create';
    return '[$op] total=${totalMs}ms '
        '| fields=${customFieldCommitMs}ms (${dirtyCustomFields}dirty) '
        '| member=${memberWriteMs}ms '
        '| pkReload=${pkReloadMs}ms '
        '| other=${_otherMs}ms '
        '| avatar=${kb(avatarBytes)} header=${kb(headerBytes)} '
        '| members=$memberCount';
  }
}

/// Bounded in-memory ring buffer of recent save traces. Newest first.
class AddMemberPerfLog {
  AddMemberPerfLog._();

  static const int _cap = 25;

  /// Observable so the diagnostics screen rebuilds when a new trace lands.
  static final ValueNotifier<List<AddMemberPerfEntry>> entries =
      ValueNotifier<List<AddMemberPerfEntry>>(const []);

  static void record(AddMemberPerfEntry entry) {
    final next = <AddMemberPerfEntry>[entry, ...entries.value];
    if (next.length > _cap) next.removeRange(_cap, next.length);
    entries.value = next;
    // Mirror to console for dev builds / anyone watching `flutter logs`.
    debugPrint('[add-perf] ${entry.format()}');
  }

  static void clear() => entries.value = const [];
}
