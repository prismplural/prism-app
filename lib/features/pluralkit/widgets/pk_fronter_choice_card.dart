import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// A card-style tappable widget for the "Who's fronting?" resolution sheet.
///
/// Displays a [title] and [subtitle]. When [recommended] is true, a check-circle
/// icon and "Recommended" badge are shown on the trailing side. Disabled when
/// [onTap] is null.
class PkFronterChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool recommended;
  final VoidCallback? onTap;

  const PkFronterChoiceCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.recommended = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recommendedLabel = context.l10n.pluralkitWhosFrontingRecommended;

    final semanticLabel = recommended
        ? '$title${subtitle.isNotEmpty ? '. $subtitle' : ''}. $recommendedLabel'
        : '$title${subtitle.isNotEmpty ? '. $subtitle' : ''}';

    return Semantics(
      container: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: PrismSurface(
        padding: const EdgeInsets.all(16),
        borderRadius: PrismTokens.radiusSmall,
        tone: recommended ? PrismSurfaceTone.accent : PrismSurfaceTone.subtle,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The recommendation badge is intrinsic (icon plus word) and is
              // not a flexible child, so at large text the word alone can be
              // wider than the whole card: the Expanded title then gets zero
              // width and the row paints past its edge. Cap the badge to a
              // share of the row so its word wraps at the requested size
              // instead; the icon keeps its graphic size, nothing is scaled
              // down, and the card's semantics still say "Recommended".
              final badgeMaxWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth * 0.45
                  : double.infinity;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (recommended) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: badgeMaxWidth),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PhosphorIcon(
                            key: const Key(
                              'pk_fronter_choice_card_recommended_icon',
                            ),
                            AppIcons.checkCircle,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            recommendedLabel,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
