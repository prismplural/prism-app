import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_live_fronters_notice.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';

const pkUnmappedFrontersDismissedHashesPrefsKey =
    'pk_unmapped_fronters_notice_dismissed_hashes';

class PkUnmappedFrontersNoticeState {
  final PkUnmappedFrontersNotice? currentNotice;
  final Set<String> dismissedFingerprintHashes;

  const PkUnmappedFrontersNoticeState({
    this.currentNotice,
    this.dismissedFingerprintHashes = const {},
  });

  PkUnmappedFrontersNoticeState copyWith({
    PkUnmappedFrontersNotice? currentNotice,
    Set<String>? dismissedFingerprintHashes,
    bool clearCurrentNotice = false,
  }) {
    return PkUnmappedFrontersNoticeState(
      currentNotice: clearCurrentNotice
          ? null
          : currentNotice ?? this.currentNotice,
      dismissedFingerprintHashes:
          dismissedFingerprintHashes ?? this.dismissedFingerprintHashes,
    );
  }

  bool isDismissed(PkUnmappedFrontersNotice notice) =>
      dismissedFingerprintHashes.contains(notice.dismissalKey);
}

class PkUnmappedFrontersNoticeController
    extends AsyncNotifier<PkUnmappedFrontersNoticeState> {
  @override
  Future<PkUnmappedFrontersNoticeState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed =
        prefs.getStringList(pkUnmappedFrontersDismissedHashesPrefsKey) ??
        const <String>[];
    return PkUnmappedFrontersNoticeState(
      dismissedFingerprintHashes: dismissed.toSet(),
    );
  }

  Future<void> publish(PkUnmappedFrontersNotice notice) async {
    final current = await _loadedState();
    state = AsyncValue.data(
      current.isDismissed(notice)
          ? current.copyWith(clearCurrentNotice: true)
          : current.copyWith(currentNotice: notice),
    );
  }

  Future<void> applyLiveFrontersSummary(PkSyncSummary summary) async {
    final notice = summary.liveUnmappedFronters;
    if (notice != null) {
      await publish(notice);
      return;
    }
    if (!summary.observedLiveFronters) return;

    final current = await _loadedState();
    final currentNotice = current.currentNotice;
    if (currentNotice == null) return;

    state = AsyncValue.data(current.copyWith(clearCurrentNotice: true));
  }

  Future<void> dismiss(PkUnmappedFrontersNotice notice) async {
    final current = await _loadedState();
    final nextDismissed = {...current.dismissedFingerprintHashes}
      ..add(notice.dismissalKey);
    await _persistDismissedHashes(nextDismissed);
    state = AsyncValue.data(
      current.copyWith(
        dismissedFingerprintHashes: nextDismissed,
        clearCurrentNotice:
            current.currentNotice?.dismissalKey == notice.dismissalKey,
      ),
    );
  }

  Future<void> dismissCurrent() async {
    final current = await _loadedState();
    final notice = current.currentNotice;
    if (notice == null) return;
    await dismiss(notice);
  }

  Future<void> clear() async {
    final current = await _loadedState();
    state = AsyncValue.data(current.copyWith(clearCurrentNotice: true));
  }

  Future<void> clearDismissals() async {
    final current = await _loadedState();
    await _persistDismissedHashes(const <String>{});
    state = AsyncValue.data(
      current.copyWith(dismissedFingerprintHashes: const <String>{}),
    );
  }

  Future<PkUnmappedFrontersNoticeState> _loadedState() async {
    final current = state.value;
    if (current != null) return current;
    return future;
  }

  Future<void> _persistDismissedHashes(Set<String> hashes) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = hashes.toList(growable: false)..sort();
    await prefs.setStringList(
      pkUnmappedFrontersDismissedHashesPrefsKey,
      sorted,
    );
  }
}

final pkUnmappedFrontersNoticeProvider =
    AsyncNotifierProvider<
      PkUnmappedFrontersNoticeController,
      PkUnmappedFrontersNoticeState
    >(PkUnmappedFrontersNoticeController.new);
