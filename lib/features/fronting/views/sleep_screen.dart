import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

class SleepScreen extends ConsumerWidget {
  const SleepScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: l10n.sleepScreenTitle,
        showBackButton: showBackButton,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.navSettings,
            tooltip: l10n.sleepScreenSettingsTooltip,
            onPressed: () => context.push(AppRoutePaths.settingsFeaturesSleep),
          ),
          PrismTopBarAction(
            icon: AppIcons.add,
            tooltip: l10n.sleepScreenAddTooltip,
            onPressed: () {},
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: EmptyState(
        icon: Icon(AppIcons.navSleep),
        title: l10n.sleepEmptyTitle,
        subtitle: l10n.sleepEmptyBody,
        actionLabel: l10n.sleepScreenAddTooltip,
        onAction: () {},
      ),
    );
  }
}
