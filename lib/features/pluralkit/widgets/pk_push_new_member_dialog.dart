import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Shows the "Push {name} to PluralKit?" dialog immediately after a member
/// has been created via [`AddEditMemberSheet`] while PluralKit is paired but
/// general push sync is disabled (either by direction or by Live Fronts Only
/// mode).
///
/// The dialog gives the user a one-tap escape hatch to push the new member
/// to PluralKit without changing any global sync settings, OR to mark the
/// member durably Prism-only via [`Member.pluralkitSyncIgnored`].
///
/// Returns:
/// - `true`  if the user picked "Push once" AND the push completed (success
///           snackbar shown).
/// - `false` if the user picked "Keep local" (the member is updated with
///           `pluralkitSyncIgnored: true`).
/// - `null`  if the user dismissed the dialog via the backdrop.
///
/// Push failures are surfaced via [`PrismToast.error`] and the dialog stays
/// open so the user can try again or pick "Keep local."
Future<bool?> showPkPushNewMemberDialog(
  BuildContext context, {
  required String memberId,
  required String memberName,
}) {
  final l10n = context.l10n;
  return PrismDialog.show<bool>(
    context: context,
    title: l10n.pkPushNewMemberDialogTitle(memberName),
    builder: (_) => _PkPushNewMemberDialogBody(
      memberId: memberId,
      memberName: memberName,
    ),
  );
}

class _PkPushNewMemberDialogBody extends ConsumerStatefulWidget {
  const _PkPushNewMemberDialogBody({
    required this.memberId,
    required this.memberName,
  });

  final String memberId;
  final String memberName;

  @override
  ConsumerState<_PkPushNewMemberDialogBody> createState() =>
      _PkPushNewMemberDialogBodyState();
}

class _PkPushNewMemberDialogBodyState
    extends ConsumerState<_PkPushNewMemberDialogBody> {
  bool _busy = false;

  Future<void> _onPushOnce() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Capture context-bound handles BEFORE the async gap so post-await we
    // don't reference the BuildContext directly.
    final navigator = Navigator.of(context, rootNavigator: true);
    final l10n = context.l10n;
    final successMessage = l10n.pkPushNewMemberDialogSuccess(widget.memberName);
    final BuildContext captured = context;
    try {
      await ref
          .read(pkOneShotPushServiceProvider)
          .pushSingleMember(widget.memberId);
      if (!captured.mounted) return;
      PrismToast.success(captured, message: successMessage);
      navigator.pop(true);
    } catch (e) {
      if (!captured.mounted) return;
      PrismToast.error(
        captured,
        message: l10n.pkPushNewMemberDialogError(
          widget.memberName,
          e.toString(),
        ),
      );
      setState(() => _busy = false);
    }
  }

  Future<void> _onKeepLocal() async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context, rootNavigator: true);
    try {
      final repo = ref.read(memberRepositoryProvider);
      final fresh = await repo.getMemberById(widget.memberId);
      if (fresh != null && !fresh.isDeleted) {
        await repo.updateMember(fresh.copyWith(pluralkitSyncIgnored: true));
      }
      if (!mounted) return;
      navigator.pop(false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.pkPushNewMemberDialogBody(widget.memberName),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            PrismButton(
              label: l10n.pkPushNewMemberDialogKeepLocal,
              onPressed: _onKeepLocal,
              tone: PrismButtonTone.outlined,
              enabled: !_busy,
            ),
            PrismButton(
              label: l10n.pkPushNewMemberDialogConfirm,
              onPressed: _onPushOnce,
              tone: PrismButtonTone.filled,
              enabled: !_busy,
              isLoading: _busy,
            ),
          ],
        ),
      ],
    );
  }
}
