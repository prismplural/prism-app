import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/widgets/navigation_layout_editor.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

class NavigationStep extends ConsumerWidget {
  const NavigationStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final baseLayout = onboardingNavLayout(onboarding);
    final settings = ref
        .watch(systemSettingsProvider)
        .whenOrNull(data: (value) => value);
    final terms = resolveTerminology(
      context.l10n,
      onboarding.selectedTerminology,
      customSingular: onboarding.customTermSingular,
      customPlural: onboarding.customTermPlural,
      useEnglish: onboarding.terminologyUseEnglish,
    );
    final hasDraftLayout =
        onboarding.navBarItems.isNotEmpty ||
        onboarding.navBarOverflowItems.isNotEmpty;
    final layout = hasDraftLayout
        ? baseLayout
        : _defaultOnboardingNavLayoutForDevice(
            context,
            state: onboarding,
            baseLayout: baseLayout,
            terminologyPlural: terms.plural,
          );
    if (onboarding.navBarItems.isEmpty &&
        onboarding.navBarOverflowItems.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final latest = ref.read(onboardingProvider);
        if (latest.navBarItems.isNotEmpty ||
            latest.navBarOverflowItems.isNotEmpty) {
          return;
        }
        final settingsHasNav =
            (settings?.navBarItems.isNotEmpty ?? false) ||
            (settings?.navBarOverflowItems.isNotEmpty ?? false);
        final seedFromSettings =
            settingsHasNav &&
            !latest.wasImportedFromPluralKit &&
            !latest.wasImportedFromSimplyPlural;
        final latestLayout = onboardingNavLayout(latest);
        final defaultLayout = _defaultOnboardingNavLayoutForDevice(
          context,
          state: latest,
          baseLayout: latestLayout,
          terminologyPlural: terms.plural,
        );
        notifier.seedNavLayoutIfUnset(
          primary: seedFromSettings
              ? settings!.navBarItems
              : defaultLayout.primary.map((tab) => tab.id.name).toList(),
          overflow: seedFromSettings
              ? settings!.navBarOverflowItems
              : defaultLayout.overflow.map((tab) => tab.id.name).toList(),
        );
      });
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      child: NavigationLayoutEditor(
        primaryTabs: layout.primary,
        overflowTabs: layout.overflow,
        flags: onboardingFeatureFlags(onboarding),
        terminologyPlural: terms.plural,
        showDisabledFeatures: false,
        showLayoutTitle: false,
        adaptSavedLayoutToDeviceWidth: false,
        sectionPadding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        intro: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Text(
            context.l10n.onboardingNavigationMoreHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? AppColors.mutedTextDark
                  : AppColors.mutedTextLight,
            ),
          ),
        ),
        onLayoutChanged: (primary, overflow) {
          notifier.setNavLayout(
            primary: primary.map((tab) => tab.id.name).toList(),
            overflow: overflow.map((tab) => tab.id.name).toList(),
          );
        },
      ),
    );
  }
}

NavLayout _defaultOnboardingNavLayoutForDevice(
  BuildContext context, {
  required OnboardingState state,
  required NavLayout baseLayout,
  required String terminologyPlural,
}) {
  final settingsTab = baseLayout.primary
      .where((tab) => tab.id == AppShellTabId.settings)
      .firstOrNull;
  if (settingsTab == null) return baseLayout;

  final candidatesBeforeSettings = [
    for (final tab in baseLayout.primary)
      if (tab.id != AppShellTabId.settings) tab,
  ];

  for (
    var primaryCount = baseLayout.primary.length;
    primaryCount >= 2;
    primaryCount--
  ) {
    final primary = [
      ...candidatesBeforeSettings.take(primaryCount - 1),
      settingsTab,
    ];
    final primaryIds = primary.map((tab) => tab.id).toSet();
    final overflow = [
      for (final tab in baseLayout.primary)
        if (!primaryIds.contains(tab.id)) tab,
      ...baseLayout.overflow,
    ];
    final normalized = normalizeNavLayout(
      primaryIds: primary.map((tab) => tab.id.name).toList(),
      overflowIds: overflow.map((tab) => tab.id.name).toList(),
      flags: onboardingFeatureFlags(state),
    );
    final rendered = computeAdaptiveNavLayoutForCurrentDevice(
      context,
      primary: normalized.primary,
      overflow: normalized.overflow,
      terminologyPlural: terminologyPlural,
    );
    if (_sameTabIds(rendered.primaryTabs, normalized.primary)) {
      return (primary: normalized.primary, overflow: normalized.overflow);
    }
  }

  final fallback = normalizeNavLayout(
    primaryIds: [AppShellTabId.home.name, AppShellTabId.settings.name],
    overflowIds: [
      for (final tab in baseLayout.primary)
        if (tab.id != AppShellTabId.home && tab.id != AppShellTabId.settings)
          tab.id.name,
      ...baseLayout.overflow.map((tab) => tab.id.name),
    ],
    flags: onboardingFeatureFlags(state),
  );
  return (primary: fallback.primary, overflow: fallback.overflow);
}

bool _sameTabIds(List<AppShellTab> left, List<AppShellTab> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i].id != right[i].id) return false;
  }
  return true;
}
