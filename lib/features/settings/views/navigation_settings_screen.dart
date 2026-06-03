import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/features_settings_screen.dart';
import 'package:prism_plurality/features/settings/widgets/navigation_layout_editor.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/detail_side_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

export 'package:prism_plurality/features/settings/widgets/navigation_layout_editor.dart'
    show computeAdaptiveNavLayoutForCurrentDevice;

class NavigationSettingsScreen extends ConsumerWidget {
  const NavigationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryTabs = ref.watch(activeNavBarTabsProvider);
    final overflowTabs = ref.watch(navBarOverflowTabsProvider);
    final flags = ref.watch(featureFlagsProvider);
    final syncNavigationEnabled = ref.watch(syncNavigationEnabledProvider);
    final terms = watchTerminology(context, ref);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.navigationSettingsTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(top: 8, bottom: NavBarInset.of(context)),
        children: [
          PrismSection(
            title: context.l10n.navigationPreferences,
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  PrismSwitchRow(
                    title: context.l10n.syncNavigationLayoutTitle,
                    subtitle: context.l10n.syncNavigationLayoutSubtitle,
                    value: syncNavigationEnabled,
                    onChanged: (v) => ref
                        .read(settingsNotifierProvider.notifier)
                        .updateSyncNavigationEnabled(v),
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                  PrismSwitchRow(
                    title: context.l10n.navigationShowViewToggleTitle,
                    subtitle: context.l10n.navigationShowViewToggleSubtitle,
                    value:
                        ref
                            .watch(showFrontingViewToggleProvider)
                            .whenOrNull(data: (v) => v) ??
                        true,
                    onChanged: (v) => ref
                        .read(showFrontingViewToggleProvider.notifier)
                        .setEnabled(v),
                  ),
                ],
              ),
            ),
          ),
          NavigationLayoutEditor(
            primaryTabs: primaryTabs,
            overflowTabs: overflowTabs,
            flags: flags,
            terminologyPlural: terms.plural,
            onDisabledFeatureTap: () {
              if (shouldUseDetailSideSheet(context)) {
                showDetailSideSheet(
                  context,
                  builder: (_) => const FeaturesSettingsScreen(),
                );
              } else {
                context.push(AppRoutePaths.settingsFeatures);
              }
            },
            onLayoutChanged: (primary, overflow) {
              ref
                  .read(settingsNotifierProvider.notifier)
                  .updateNavigationLayout(
                    navBarItems: primary.map((tab) => tab.id.name).toList(),
                    navBarOverflowItems: overflow
                        .map((tab) => tab.id.name)
                        .toList(),
                  );
            },
          ),
        ],
      ),
    );
  }
}
