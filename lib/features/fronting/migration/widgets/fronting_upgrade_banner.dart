/// Phase 5C — banner shown on the home screen when the user has
/// deferred the per-member fronting upgrade.
///
/// Visibility is keyed on
/// `system_settings.pending_fronting_migration_mode == 'deferred'` —
/// renders nothing for `notStarted` (the modal is auto-presented by the
/// app shell instead) and nothing for `complete` (no work left).
///
/// Tapping the banner re-opens the upgrade modal in dismissible mode
/// (the user already chose to defer once; we don't trap them again).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/fronting/migration/fronting_migration_service.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/fronting/migration/views/fronting_upgrade_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/info_banner.dart';

class FrontingUpgradeBanner extends ConsumerWidget {
  const FrontingUpgradeBanner({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 0),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(frontingMigrationModeProvider).value;
    // Show the banner for both `deferred` (user opted out) and
    // `inProgress` (Codex P1 #4: post-tx cleanup partially failed and
    // can be resumed). Either way the user re-enters via the modal,
    // which adapts to whichever state is current.
    final isVisible = mode == FrontingMigrationService.modeDeferred ||
        mode == FrontingMigrationService.modeInProgress;
    if (!isVisible) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: InfoBanner(
        icon: AppIcons.warningAmberRounded,
        iconColor: theme.colorScheme.primary,
        title: context.l10n.frontingUpgradeBannerTitle,
        message: context.l10n.frontingUpgradeBannerMessage,
        buttonText: context.l10n.frontingUpgradeContinue,
        onButtonPressed: () =>
            showFrontingUpgradeSheet(context, isDismissible: true),
      ),
    );
  }
}
