import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

enum MemberFrontAction { add, replace, end }

/// Feature-local input serialization, shared by row menus and quick buttons.
/// The existing fronting service still owns all session and policy mutations.
final memberFrontActionBusyProvider =
    NotifierProvider.autoDispose<MemberFrontActionSubmission, bool>(
      MemberFrontActionSubmission.new,
    );

class MemberFrontActionSubmission extends Notifier<bool> {
  @override
  bool build() => false;

  bool _inputsReady() {
    final sessions = ref.read(activeSessionsProvider);
    final members = ref.read(allMemberListProvider);
    return !sessions.isLoading &&
        !sessions.hasError &&
        sessions.hasValue &&
        !members.isLoading &&
        !members.hasError &&
        members.hasValue;
  }

  Future<bool> submit(Member member, MemberFrontAction action) async {
    final owner = ref;
    if (!owner.mounted || state || !_inputsReady()) return false;
    state = true; // Acquire before any asynchronous durable read or mutation.
    // Preserve serialization across last-row unmount + new-page mount while
    // this operation is in flight. An actual ProviderScope disposal still wins.
    final lease = owner.keepAlive();
    try {
      final repository = owner.read(frontingSessionRepositoryProvider);
      final rows = await repository.getAllActiveSessionsUnfiltered();
      if (!owner.mounted ||
          !identical(
            owner.read(frontingSessionRepositoryProvider),
            repository,
          ) ||
          !_inputsReady()) {
        return false;
      }
      final members = owner.read(allMemberListProvider).requireValue;
      final matches = members.where((candidate) => candidate.id == member.id);
      if (matches.isEmpty) return false;
      final current = matches.first;
      if (!current.isActive || current.isDeleted) return false;
      // The repository includes sleep rows, but excludes ended/deleted rows.
      // Keep the latter checks explicit for alternate repository implementations.
      final active = rows.any(
        (session) =>
            session.memberId == member.id &&
            !session.isSleep &&
            !session.isDeleted &&
            session.endTime == null,
      );
      if (action == MemberFrontAction.end) {
        if (!active || current.isAlwaysFronting) return false;
      } else if (active) {
        return false;
      }
      final notifier = owner.read(frontingNotifierProvider.notifier);
      switch (action) {
        case MemberFrontAction.add:
          await notifier.startFronting([member.id]);
        case MemberFrontAction.replace:
          await notifier.replaceFronting([member.id]);
        case MemberFrontAction.end:
          await notifier.endFronting([member.id]);
      }
      return true;
    } finally {
      if (owner.mounted) state = false;
      lease.close();
    }
  }
}

class MemberContextAction {
  const MemberContextAction({
    required this.label,
    required this.icon,
    this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final FutureOr<void> Function()? onSelected;
  final bool destructive;
}

/// Individual-member actions only: deliberately unrelated to front-group UX.
class MemberFrontActionsMenu extends ConsumerStatefulWidget {
  const MemberFrontActionsMenu({
    super.key,
    required this.member,
    required this.child,
    this.additionalActions = const [],
  });

  final Member member;
  final Widget child;
  final List<MemberContextAction> additionalActions;

  @override
  ConsumerState<MemberFrontActionsMenu> createState() =>
      _MemberFrontActionsMenuState();
}

class _MemberFrontActionsMenuState
    extends ConsumerState<MemberFrontActionsMenu> {
  final _popupKey = GlobalKey<BlurPopupAnchorState>();

  Future<void> _submit(MemberFrontAction action) async {
    try {
      await ref
          .read(memberFrontActionBusyProvider.notifier)
          .submit(widget.member, action);
    } catch (error) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: context.l10n.frontingErrorSwitchingFronter(error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final terms = watchFrontingTerms(context, ref);
    final sessionsState = ref.watch(activeSessionsProvider);
    final rosterState = ref.watch(allMemberListProvider);
    final rosterReady =
        !rosterState.isLoading && !rosterState.hasError && rosterState.hasValue;
    final sessions = !sessionsState.isLoading && !sessionsState.hasError
        ? sessionsState.value
        : null;
    final busy = ref.watch(memberFrontActionBusyProvider);
    final member = widget.member;
    final active =
        sessions?.any(
          (session) => session.memberId == member.id && !session.isSleep,
        ) ??
        false;
    final actions = <MemberContextAction>[
      if (member.isActive &&
          !member.isDeleted &&
          sessions != null &&
          rosterReady)
        if (active && member.isAlwaysFronting)
          MemberContextAction(
            label: terms.alwaysActiveLabel,
            icon: AppIcons.flashOn,
          )
        else if (active)
          MemberContextAction(
            label: terms.endCurrentAction,
            icon: AppIcons.stopRounded,
            onSelected: busy ? null : () => _submit(MemberFrontAction.end),
          )
        else ...[
          MemberContextAction(
            label: terms.addAction,
            icon: AppIcons.add,
            onSelected: busy ? null : () => _submit(MemberFrontAction.add),
          ),
          MemberContextAction(
            label: terms.replaceCurrentAction,
            icon: AppIcons.flashOn,
            onSelected: busy ? null : () => _submit(MemberFrontAction.replace),
          ),
        ],
      ...widget.additionalActions,
    ];
    void open() {
      _popupKey.currentState?.show();
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f10, shift: true): open,
        const SingleActivator(LogicalKeyboardKey.contextMenu): open,
      },
      child: BlurPopupAnchor(
        key: _popupKey,
        trigger: BlurPopupTrigger.longPress,
        width: 240,
        maxHeight: 360,
        semanticLabel: context.l10n.memberMoreOptionsTooltip,
        itemCount: actions.length,
        itemBuilder: (context, index, close) {
          if (index >= actions.length) return const SizedBox.shrink();
          final action = actions[index];
          final select = action.onSelected;
          return PrismListRow(
            dense: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            leading: Icon(action.icon, size: 20),
            title: Text(action.label),
            destructive: action.destructive,
            enabled: select != null,
            onTap: select == null
                ? null
                : () {
                    close();
                    unawaited(Future<void>.sync(select));
                  },
          );
        },
        child: widget.child,
      ),
    );
  }
}
