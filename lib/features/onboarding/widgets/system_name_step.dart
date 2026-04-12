import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class SystemNameStep extends ConsumerStatefulWidget {
  const SystemNameStep({super.key});

  @override
  ConsumerState<SystemNameStep> createState() => _SystemNameStepState();
}

class _SystemNameStepState extends ConsumerState<SystemNameStep> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final currentName = ref.read(onboardingProvider).systemName;
    _controller = TextEditingController(text: currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final autoFocus = !onboarding.wasImportedFromPluralKit;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.1)
                  : AppColors.parchmentElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: PrismTextField(
              controller: _controller,
              autofocus: autoFocus,
              style: TextStyle(
                color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              hintText: context.l10n.onboardingSystemNameHint,
              hintStyle: TextStyle(
                color: isDark
                    ? AppColors.warmWhite.withValues(alpha: 0.35)
                    : AppColors.warmBlack.withValues(alpha: 0.35),
                fontSize: 20,
              ),
              fieldStyle: PrismTextFieldStyle.borderless,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
              onChanged: (value) {
                ref.read(onboardingProvider.notifier).setSystemName(value);
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.onboardingSystemNameHelperText,
            style: TextStyle(
              color: isDark
                  ? AppColors.mutedTextDark
                  : AppColors.mutedTextLight,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
