import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/features_settings_screen.dart';
import 'package:prism_plurality/features/settings/widgets/navigation_layout_editor.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/adaptive_detail_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
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
    final labelVisibility = ref.watch(navBarLabelVisibilityProvider);
    final labelStyleMode = ref.watch(navBarLabelStyleProvider);
    final terms = watchTerminology(context, ref);

    Widget divider() => Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
    );

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
                  divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: _NavLabelVisibilityControl(
                      value: labelVisibility,
                      onChanged: (visibility) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateNavBarLabelVisibility(visibility),
                    ),
                  ),
                  // The text-style axis is moot when labels never render, so it
                  // only appears once labels are shown somewhere.
                  if (labelVisibility != NavBarLabelVisibility.never) ...[
                    divider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: _NavLabelStyleControl(
                        value: labelStyleMode,
                        onChanged: (style) => ref
                            .read(settingsNotifierProvider.notifier)
                            .updateNavBarLabelStyle(style),
                      ),
                    ),
                  ],
                  divider(),
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
            labelVisibility: labelVisibility,
            labelStyleMode: labelStyleMode,
            onDisabledFeatureTap: () {
              showAdaptiveDetailSurface<void>(
                context: context,
                builder: (_) => const FeaturesSettingsScreen(),
                route: (context) =>
                    context.push(AppRoutePaths.settingsFeatures),
              );
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

/// Shared titled-segmented-control scaffold for the two label axes.
class _NavLabelControl extends StatelessWidget {
  const _NavLabelControl({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _NavLabelVisibilityControl extends StatelessWidget {
  const _NavLabelVisibilityControl({
    required this.value,
    required this.onChanged,
  });

  final NavBarLabelVisibility value;
  final ValueChanged<NavBarLabelVisibility> onChanged;

  @override
  Widget build(BuildContext context) {
    return _NavLabelControl(
      title: context.l10n.navigationLabelVisibilityTitle,
      subtitle: context.l10n.navigationLabelVisibilitySubtitle,
      child: PrismSegmentedControl<NavBarLabelVisibility>(
        selected: value,
        onChanged: onChanged,
        segments: [
          PrismSegment(
            value: NavBarLabelVisibility.always,
            label: context.l10n.navigationLabelVisibilityAlways,
          ),
          PrismSegment(
            value: NavBarLabelVisibility.whenExpanded,
            label: context.l10n.navigationLabelVisibilityWhenExpanded,
          ),
          PrismSegment(
            value: NavBarLabelVisibility.never,
            label: context.l10n.navigationLabelVisibilityNever,
          ),
        ],
      ),
    );
  }
}

class _NavLabelStyleControl extends StatelessWidget {
  const _NavLabelStyleControl({required this.value, required this.onChanged});

  final NavBarLabelStyle value;
  final ValueChanged<NavBarLabelStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return _NavLabelControl(
      title: context.l10n.navigationLabelStyleTitle,
      subtitle: context.l10n.navigationLabelStyleSubtitle,
      child: PrismSegmentedControl<NavBarLabelStyle>(
        selected: value,
        onChanged: onChanged,
        segments: [
          PrismSegment(
            value: NavBarLabelStyle.full,
            label: context.l10n.navigationLabelStyleFull,
          ),
          PrismSegment(
            value: NavBarLabelStyle.truncated,
            label: context.l10n.navigationLabelStyleTruncated,
          ),
        ],
      ),
    );
  }
}
