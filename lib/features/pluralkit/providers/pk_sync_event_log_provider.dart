import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

/// Maximum number of [PkSyncEventLogEntry] objects retained in the in-memory
/// ring buffer surfaced by [pkSyncEventLogProvider]. Older entries are
/// dropped from the front when this cap is exceeded.
///
/// The 200-entry size matches the Prism sync log so the two surfaces feel
/// like siblings; it's big enough to capture a few minutes of active
/// troubleshooting without runaway memory growth.
const kPkSyncEventLogMax = 200;

/// One entry in the PluralKit sync log: a [PkSyncEvent] plus the wall-clock
/// timestamp recorded when the bus delivered it.
///
/// Immutable by design — [PkSyncEventLogNotifier] always reassigns a fresh
/// list when a new event arrives so Riverpod consumers see distinct
/// identities and rebuild correctly.
class PkSyncEventLogEntry {
  const PkSyncEventLogEntry({required this.timestamp, required this.event});

  /// Wall-clock time the event was observed by [PkSyncEventLogNotifier]. The
  /// originating service may have produced it slightly earlier, but the
  /// difference is negligible for a UI-facing troubleshooting log.
  final DateTime timestamp;

  /// The structured event payload. Subclass identity drives [summary],
  /// [data], and [isError].
  final PkSyncEvent event;

  /// `HH:MM:SS` zero-padded local time, suitable for the leading column in
  /// the debug-log row. Format matches `SyncEventLogEntry.timeLabel` in
  /// `core/sync/prism_sync_providers.dart` so the two screens render the
  /// same way.
  String get timeLabel =>
      '${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}:'
      '${timestamp.second.toString().padLeft(2, '0')}';

  /// Human-readable one-liner used as the tile title. Delegates to the
  /// event so adding a new event kind is a single-file change.
  String get summary => event.summary;

  /// JSON payload for the expandable JSON drawer. Same map shape that the
  /// copy-to-clipboard action serializes.
  Map<String, dynamic> get data => event.toJson();

  /// Whether the row should render with the error-color leading icon.
  bool get isError => event.isError;
}

/// Session-scoped ring buffer of [PkSyncEventLogEntry] objects observed
/// from [pkSyncEventBusProvider].
///
/// The notifier subscribes once in [build]; the subscription is cancelled
/// when the Riverpod scope tears down. Tests (and `app.dart` in production)
/// must keep at least one listener attached so the notifier stays alive —
/// otherwise events emitted while no widget is observing will be lost
/// because broadcast streams don't buffer.
class PkSyncEventLogNotifier extends Notifier<List<PkSyncEventLogEntry>> {
  @override
  List<PkSyncEventLogEntry> build() {
    final bus = ref.watch(pkSyncEventBusProvider);
    final sub = bus.stream.listen((event) {
      final next = [
        ...state,
        PkSyncEventLogEntry(timestamp: DateTime.now(), event: event),
      ];
      final overflow = next.length - kPkSyncEventLogMax;
      state = overflow > 0 ? next.sublist(overflow) : next;
    });
    ref.onDispose(sub.cancel);
    return const [];
  }

  /// Empties the buffer. The next emitted event will start a fresh list.
  void clear() {
    state = const [];
  }
}

/// App-wide PluralKit sync log. Keep this provider alive across the
/// session — `app.dart` does so via a `ref.listen` so events emitted before
/// the debug screen opens are still recorded.
final pkSyncEventLogProvider =
    NotifierProvider<PkSyncEventLogNotifier, List<PkSyncEventLogEntry>>(
      PkSyncEventLogNotifier.new,
    );
