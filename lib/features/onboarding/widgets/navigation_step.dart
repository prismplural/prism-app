import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final layout = onboardingNavLayout(onboarding);
    final settings = ref
        .watch(systemSettingsProvider)
        .whenOrNull(data: (value) => value);
    if (onboarding.navBarItems.isEmpty &&
        onboarding.navBarOverflowItems.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
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
        notifier.seedNavLayoutIfUnset(
          primary: seedFromSettings
              ? settings!.navBarItems
              : latestLayout.primary.map((tab) => tab.id.name).toList(),
          overflow: seedFromSettings
              ? settings!.navBarOverflowItems
              : latestLayout.overflow.map((tab) => tab.id.name).toList(),
        );
      });
    }
    final terms = resolveTerminology(
      context.l10n,
      onboarding.selectedTerminology,
      customSingular: onboarding.customTermSingular,
      customPlural: onboarding.customTermPlural,
      useEnglish: onboarding.terminologyUseEnglish,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      child: NavigationLayoutEditor(
        primaryTabs: layout.primary,
        overflowTabs: layout.overflow,
        flags: onboardingFeatureFlags(onboarding),
        terminologyPlural: terms.plural,
        showDisabledFeatures: false,
        showLayoutTitle: false,
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
