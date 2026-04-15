import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';

class GifConsentDialog extends StatelessWidget {
  const GifConsentDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await PrismDialog.show<bool>(
      context: context,
      title: context.l10n.chatGifConsentTitle,
      message: context.l10n.chatGifConsentIntro,
      barrierDismissible: false,
      actions: [
        PrismButton(
          label: context.l10n.chatGifConsentDecline,
          tone: PrismButtonTone.outlined,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PrismButton(
          label: context.l10n.chatGifConsentEnable,
          tone: PrismButtonTone.filled,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      builder: (_) => const GifConsentDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    Widget section(IconData icon, String title, String body) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section(
          AppIcons.search,
          context.l10n.chatGifConsentRelayTitle,
          context.l10n.chatGifConsentRelayBody,
        ),
        section(
          AppIcons.gif,
          context.l10n.chatGifConsentKlipyTitle,
          context.l10n.chatGifConsentKlipyBody,
        ),
        section(
          AppIcons.playArrowRounded,
          context.l10n.chatGifConsentMediaTitle,
          context.l10n.chatGifConsentMediaBody,
        ),
      ],
    );
  }
}
