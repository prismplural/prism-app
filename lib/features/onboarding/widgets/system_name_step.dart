import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class SystemNameStep extends ConsumerStatefulWidget {
  const SystemNameStep({super.key});

  // The field and helper geometry, shared with the onboarding screen's height
  // budget so its measurement can never drift from what is rendered here.
  static const double fieldFontSize = 20;
  static const FontWeight fieldFontWeight = FontWeight.w500;
  static const double fieldVerticalPadding = 18;
  static const double fieldHorizontalPadding = 20;
  static const double helperFontSize = 14;
  static const double fieldToHelperGap = 16;

  /// Text style of the name field, resolved for [context].
  static TextStyle fieldTextStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
      fontSize: fieldFontSize,
      fontWeight: fieldFontWeight,
    );
  }

  /// Text style of the helper copy, resolved for [context].
  static TextStyle helperTextStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      color: isDark ? AppColors.mutedTextDark : AppColors.mutedTextLight,
      fontSize: helperFontSize,
    );
  }

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
    final wasImported =
        onboarding.wasImportedFromPluralKit ||
        onboarding.wasImportedFromSimplyPlural;
    final autoFocus = !wasImported;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final helperText = wasImported && onboarding.systemName.trim().isNotEmpty
        ? context.l10n.onboardingSystemNameHelperTextImported
        : context.l10n.onboardingSystemNameHelperText;

    // The body is the space the screen has left between its pinned header and
    // bottom bar; with the keyboard up that can be less than the field plus its
    // helper copy, and the Column then reported 43 / 143 / 609dp of bottom
    // overflow on a 320x568 phone at 1x / 1.5x / 3.375x with nothing to scroll.
    // It scrolls now and keeps its centred look whenever it fits. The controller,
    // the external-name listen, autofocus and onChanged are untouched.
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight;
        final availableHeight = viewportHeight.isFinite && viewportHeight > 0
            ? viewportHeight
            : 0.0;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: availableHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.warmWhite.withValues(alpha: 0.1)
                        : AppColors.parchmentElevated,
                    borderRadius: BorderRadius.circular(
                      PrismShapes.of(context).radius(12),
                    ),
                  ),
                  child: PrismTextField(
                    controller: _controller,
                    autofocus: autoFocus,
                    style: SystemNameStep.fieldTextStyle(context),
                    textAlign: TextAlign.center,
                    hintText: context.l10n.onboardingSystemNameHint,
                    hintStyle: TextStyle(
                      color: isDark
                          ? AppColors.warmWhite.withValues(alpha: 0.35)
                          : AppColors.warmBlack.withValues(alpha: 0.35),
                      fontSize: SystemNameStep.fieldFontSize,
                    ),
                    fieldStyle: PrismTextFieldStyle.borderless,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: SystemNameStep.fieldHorizontalPadding,
                      vertical: SystemNameStep.fieldVerticalPadding,
                    ),
                    onChanged: (value) {
                      ref
                          .read(onboardingProvider.notifier)
                          .setSystemName(value);
                    },
                  ),
                ),
                const SizedBox(height: SystemNameStep.fieldToHelperGap),
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
          ),
        );
      },
    );
  }
}
