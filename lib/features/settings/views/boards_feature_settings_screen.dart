import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Settings subview for the Message Boards feature.
class BoardsFeatureSettingsScreen extends ConsumerWidget {
  const BoardsFeatureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardsEnabled = ref.watch(boardsEnabledProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.featureBoardsTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              context.l10n.featureBoardsDescription,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          PrismSection(
            title: '',
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: PrismSwitchRow(
                icon: AppIcons.navBoards,
                iconColor: Colors.indigo,
                title: context.l10n.featureBoardsEnable,
                subtitle: context.l10n.featureBoardsEnableSubtitle,
                value: boardsEnabled,
                onChanged: (value) {
                  // Capture the "was disabled before this tap" state before the
                  // async write so we can fire the one-time toast after it lands.
                  final wasFreshEnable = !boardsEnabled && value;
                  final toastMessage = context.l10n.navMenuToastBoardsAdded;
                  unawaited(
                    ref
                        .read(settingsNotifierProvider.notifier)
                        .updateFeatureToggle(boardsEnabled: value)
                        .then((_) {
                          if (wasFreshEnable && context.mounted) {
                            PrismToast.show(
                              context,
                              message: toastMessage,
                              icon: AppIcons.navBoards,
                            );
                          }
                        }),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
