import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// A styled dialog wrapper with consistent Prism design language.
///
/// Use [PrismDialog.show] for custom content or [PrismDialog.confirm] for a
/// standard confirmation dialog with title, message, and confirm/cancel buttons.
class PrismDialog extends StatelessWidget {
  const PrismDialog({
    super.key,
    this.title,
    this.message,
    required this.child,
    this.actions,
  });

  /// Optional title rendered as `titleLarge`.
  final String? title;

  /// Optional message rendered below the title.
  final String? message;

  /// The main body content of the dialog.
  final Widget child;

  /// Optional action row at the bottom.
  final List<Widget>? actions;

  /// Show a Prism-styled dialog with custom content.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? title,
    String? message,
    List<Widget>? actions,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) {
        final content = builder(dialogContext);

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PrismTokens.radiusLarge),
          ),
          backgroundColor: Theme.of(dialogContext).colorScheme.surface,
          child: PrismDialog(
            title: title,
            message: message,
            actions: actions,
            child: content,
          ),
        );
      },
    );
  }

  /// Show a confirmation dialog that returns `true` on confirm or `false` on
  /// cancel / dismissal.
  ///
  /// Set [destructive] to `true` to render the confirm button in the
  /// destructive tone (error color).
  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    String? message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
    bool barrierDismissible = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PrismTokens.radiusLarge),
          ),
          backgroundColor: Theme.of(dialogContext).colorScheme.surface,
          child: PrismDialog(
            title: title,
            message: message,
            actions: [
              PrismButton(
                label: cancelLabel,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              PrismButton(
                label: confirmLabel,
                onPressed: () => Navigator.of(dialogContext).pop(true),
                tone: destructive
                    ? PrismButtonTone.destructive
                    : PrismButtonTone.filled,
              ),
            ],
            child: const SizedBox.shrink(),
          ),
        );
      },
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(PrismTokens.pageHorizontalPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (message != null) ...[
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
          ],
          child,
          if (actions != null && actions!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (int i = 0; i < actions!.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  actions![i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
