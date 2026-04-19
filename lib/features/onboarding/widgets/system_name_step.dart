import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
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
    // If the name was set externally (e.g. by the SP import listener) after
    // this step was first built, sync it into the controller so the user
    // sees the pre-filled value.
    ref.listen(onboardingProvider, (prev, next) {
      if (prev?.systemName == next.systemName) return;
      if (_controller.text == next.systemName) return;
      _controller.text = next.systemName;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });

    final onboarding = ref.watch(onboardingProvider);
    final wasImported = onboarding.wasImportedFromPluralKit ||
        onboarding.wasImportedFromSimplyPlural;
    final autoFocus = !wasImported;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final helperText = wasImported && onboarding.systemName.trim().isNotEmpty
        ? context.l10n.onboardingSystemNameHelperTextImported
        : context.l10n.onboardingSystemNameHelperText;

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
              borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
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
            helperText,
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
