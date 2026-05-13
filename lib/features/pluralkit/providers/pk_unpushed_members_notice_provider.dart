import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_unpushed_members_notice.dart';
import 'package:prism_plurality/features/pluralkit/utils/pk_link_utils.dart';

const pkUnpushedMembersDismissedHashesPrefsKey =
    'pk_unpushed_members_notice_dismissed_hashes';

class PkUnpushedMembersNoticeState {
  final PkUnpushedMembersNotice? currentNotice;
  final Set<String> dismissedFingerprintHashes;

  const PkUnpushedMembersNoticeState({
    this.currentNotice,
    this.dismissedFingerprintHashes = const {},
  });

  PkUnpushedMembersNoticeState copyWith({
    PkUnpushedMembersNotice? currentNotice,
    Set<String>? dismissedFingerprintHashes,
    bool clearCurrentNotice = false,
  }) {
    return PkUnpushedMembersNoticeState(
      currentNotice: clearCurrentNotice
          ? null
          : currentNotice ?? this.currentNotice,
      dismissedFingerprintHashes:
          dismissedFingerprintHashes ?? this.dismissedFingerprintHashes,
    );
  }

  bool isDismissed(PkUnpushedMembersNotice notice) =>
      dismissedFingerprintHashes.contains(notice.dismissalKey);
}

class PkUnpushedMembersNoticeController
    extends AsyncNotifier<PkUnpushedMembersNoticeState> {
  @override
  Future<PkUnpushedMembersNoticeState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed =
        prefs.getStringList(pkUnpushedMembersDismissedHashesPrefsKey) ??
        const <String>[];
    return PkUnpushedMembersNoticeState(
      dismissedFingerprintHashes: dismissed.toSet(),
    );
  }

  Future<void> publish(PkUnpushedMembersNotice notice) async {
    final current = await _loadedState();
    state = AsyncValue.data(
      current.isDismissed(notice)
          ? current.copyWith(clearCurrentNotice: true)
          : current.copyWith(currentNotice: notice),
    );
  }

  /// Recompute the unpushed cohort from a members snapshot and publish (or
  /// clear) the notice. This controller does not subscribe to anything itself
  /// — the banner widget owns the `ref.listen` calls and feeds this method.
  Future<void> applyMembersSnapshot(
    List<Member> members, {
    required bool pkReady,
    required bool pushDisabled,
  }) async {
    if (!pkReady || !pushDisabled) {
      await clear();
      return;
    }

    final refs = <PkUnpushedMemberRef>[];
    for (final member in members) {
      if (member.isDeleted) continue;
      if (member.id == unknownSentinelMemberId) continue;
      if (hasPluralKitLink(member)) continue;
      if (member.pluralkitSyncIgnored) continue;
      refs.add(
        PkUnpushedMemberRef(
          memberId: member.id,
          memberName: member.name,
          displayName: member.displayName,
          avatarImageData: member.avatarImageData,
        ),
      );
    }

    if (refs.isEmpty) {
      await clear();
      return;
    }

    final notice = PkUnpushedMembersNotice(refs: refs);
    final current = await _loadedState();
    if (current.isDismissed(notice)) {
      await clear();
      return;
    }
    await publish(notice);
  }

  Future<void> dismiss(PkUnpushedMembersNotice notice) async {
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

  Future<PkUnpushedMembersNoticeState> _loadedState() async {
    final current = state.value;
    if (current != null) return current;
    return future;
  }

  Future<void> _persistDismissedHashes(Set<String> hashes) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = hashes.toList(growable: false)..sort();
    await prefs.setStringList(
      pkUnpushedMembersDismissedHashesPrefsKey,
      sorted,
    );
  }
}

final pkUnpushedMembersNoticeProvider =
    AsyncNotifierProvider<
      PkUnpushedMembersNoticeController,
      PkUnpushedMembersNoticeState
    >(PkUnpushedMembersNoticeController.new);
