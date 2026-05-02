import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Confirm-then-batch-delete every session in a multi-contributor period.
///
/// Returns true only when the user confirmed AND every per-session delete
/// succeeded; false on cancel or any failure (caller uses this to decide
/// whether to pop the route). On a partial-failure mid-loop, surfaces a
/// toast and stops — sync handles eventual consistency for the deletes
/// that already landed; the user can retry.
Future<bool> confirmAndDeletePeriod(
  BuildContext context,
  WidgetRef ref, {
  required List<String> sessionIds,
  required List<Member> contributors,
}) async {
  final names = contributors.map((m) => m.name).join(', ');
  final confirmed = await PrismDialog.confirm(
    context: context,
    title: context.l10n.frontingDeletePeriodTitle,
    message: context.l10n.frontingDeletePeriodMessage(
      sessionIds.length,
      names,
    ),
    confirmLabel: context.l10n.delete,
    destructive: true,
  );
  if (!confirmed) return false;
  Haptics.heavy();
  final repo = ref.read(frontingSessionRepositoryProvider);
  for (final id in sessionIds) {
    try {
      await repo.deleteSession(id);
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.frontingErrorSavingSession(e.toString()),
        );
      }
      return false;
    }
  }
  return true;
}
