import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class ChatSetupStep extends ConsumerStatefulWidget {
  const ChatSetupStep({super.key});

  @override
  ConsumerState<ChatSetupStep> createState() => _ChatSetupStepState();
}

class _ChatSetupStepState extends ConsumerState<ChatSetupStep> {
  final _customChannelController = TextEditingController();

  Map<String, String> _buildSuggestedChannels(
    AppLocalizations l10n,
    Terminology terms,
  ) => {
    l10n.onboardingChatChannelAllMembers(terms.plural, terms.pluralLower):
        '\u{1F465}',
    l10n.onboardingChatChannelVenting: '\u{1F62E}\u200D\u{1F4A8}',
    l10n.onboardingChatChannelPlanning: '\u{1F4CB}',
    l10n.onboardingChatChannelJournal: '\u{1F4D3}',
    l10n.onboardingChatChannelUpdates: '\u{1F4E2}',
    l10n.onboardingChatChannelRandom: '\u{1F3B2}',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seed localized default channels on first render. Uses a post-frame
    // callback to avoid calling the notifier during the build phase.
    final l10n = context.l10n;
    final onboarding = ref.read(onboardingProvider);
    final terms = resolveTerminology(
      l10n,
      onboarding.selectedTerminology,
      customSingular: onboarding.customTermSingular,
      customPlural: onboarding.customTermPlural,
      useEnglish: onboarding.terminologyUseEnglish,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(onboardingProvider.notifier)
          .seedDefaultChannels(
            allMembersName: l10n.onboardingChatChannelAllMembers(
              terms.plural,
              terms.pluralLower,
            ),
            ventingName: l10n.onboardingChatChannelVenting,
          );
    });
  }

  @override
  void dispose() {
    _customChannelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final terms = resolveTerminology(
      context.l10n,
      onboarding.selectedTerminology,
      customSingular: onboarding.customTermSingular,
      customPlural: onboarding.customTermPlural,
      useEnglish: onboarding.terminologyUseEnglish,
    );
    final suggestedChannels = _buildSuggestedChannels(context.l10n, terms);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.onboardingChatSuggestedChannels,
            style: theme.textTheme.labelLarge?.copyWith(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.8)
                  : AppColors.warmBlack.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),

          // Suggested channels
          ...suggestedChannels.entries.map((entry) {
            final isSelected = onboarding.selectedChannels.containsKey(
              entry.key,
            );
            final isAllMembers = entry.key == onboarding.allMembersChannelKey;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: isAllMembers
                    ? null
                    : () => notifier.toggleChannel(entry.key, entry.value),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark
                              ? AppColors.warmWhite.withValues(alpha: 0.15)
                              : AppColors.parchmentElevated)
                        : (isDark
                              ? AppColors.warmWhite.withValues(alpha: 0.07)
                              : AppColors.warmBlack.withValues(alpha: 0.04)),
                    borderRadius: BorderRadius.circular(
                      PrismShapes.of(context).radius(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(entry.value, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: isDark
                                ? AppColors.warmWhite
                                : AppColors.warmBlack,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isAllMembers)
                        Icon(
                          AppIcons.lock,
                          size: 16,
                          color: isDark
                              ? AppColors.warmWhite.withValues(alpha: 0.4)
                              : AppColors.warmBlack.withValues(alpha: 0.4),
                        )
                      else
                        Icon(
                          isSelected
                              ? AppIcons.checkCircle
                              : AppIcons.circleOutlined,
                          color: isSelected
                              ? primary
                              : (isDark
                                    ? AppColors.warmWhite.withValues(alpha: 0.3)
                                    : AppColors.warmBlack.withValues(
                                        alpha: 0.3,
                                      )),
                          size: 22,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 20),

          // Custom channel section
          Text(
            context.l10n.onboardingChatCustomChannel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.8)
                  : AppColors.warmBlack.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.warmWhite.withValues(alpha: 0.1)
                        : AppColors.parchmentElevated,
                    borderRadius: BorderRadius.circular(
                      PrismShapes.of(context).radius(10),
                    ),
                  ),
                  child: PrismTextField(
                    controller: _customChannelController,
                    style: TextStyle(
                      color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
                    ),
                    hintText: context.l10n.onboardingChatChannelNameHint,
                    hintStyle: TextStyle(
                      color: isDark
                          ? AppColors.warmWhite.withValues(alpha: 0.35)
                          : AppColors.warmBlack.withValues(alpha: 0.35),
                    ),
                    fieldStyle: PrismTextFieldStyle.borderless,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  final name = _customChannelController.text.trim();
                  if (name.isNotEmpty) {
                    notifier.addCustomChannel(name, '\u{1F4AC}');
                    _customChannelController.clear();
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(
                      PrismShapes.of(context).radius(10),
                    ),
                  ),
                  child: Icon(
                    AppIcons.add,
                    color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),

          // Show custom channels added
          if (onboarding.selectedChannels.keys
              .where((k) => !suggestedChannels.containsKey(k))
              .isNotEmpty) ...[
            const SizedBox(height: 12),
            ...onboarding.selectedChannels.entries
                .where((e) => !suggestedChannels.containsKey(e.key))
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.warmWhite.withValues(alpha: 0.12)
                            : AppColors.parchmentElevated,
                        borderRadius: BorderRadius.circular(
                          PrismShapes.of(context).radius(10),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            entry.value,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              entry.key,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.warmBlack,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                notifier.toggleChannel(entry.key, entry.value),
                            child: Icon(
                              AppIcons.close,
                              size: 18,
                              color: isDark
                                  ? AppColors.warmWhite.withValues(alpha: 0.5)
                                  : AppColors.warmBlack.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
