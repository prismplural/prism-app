import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// Extract the leading emoji from a string, if any.
String extractEmoji(String text) {
  if (text.isEmpty) return '';
  // Match common emoji patterns at start of string
  final emojiRegex = RegExp(
    r'^(\p{Emoji_Presentation}|\p{Emoji}\uFE0F)',
    unicode: true,
  );
  final match = emojiRegex.firstMatch(text);
  return match?.group(0) ?? '';
}

/// Remove the leading emoji from a string.
String removeEmoji(String text) {
  final emoji = extractEmoji(text);
  if (emoji.isEmpty) return text;
  return text.substring(emoji.length).trimLeft();
}

/// A suggestion item for the empty state view.
class EmptyStateSuggestion {
  const EmptyStateSuggestion({required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;
}

/// Generic reusable empty state.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.iconColor,
    this.suggestions,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final Color? iconColor;
  final List<EmptyStateSuggestion>? suggestions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = iconColor ?? theme.colorScheme.onSurfaceVariant;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: SizedBox.square(
                  dimension: 34,
                  child: Opacity(
                    opacity: iconColor == null ? 0.72 : 1,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: IconTheme(
                        data: IconThemeData(size: 34, color: color),
                        child: icon,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),

              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.82,
                  ),
                ),
                textAlign: TextAlign.center,
              ),

              if (suggestions != null && suggestions!.isNotEmpty) ...[
                const SizedBox(height: 18),
                _SuggestionsBox(suggestions: suggestions!),
              ],

              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 22),
                PrismButton(
                  label: actionLabel!,
                  icon: actionIcon,
                  onPressed: onAction!,
                  tone: PrismButtonTone.filled,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionsBox extends StatelessWidget {
  const _SuggestionsBox({required this.suggestions});
  final List<EmptyStateSuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.suggestions,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final suggestion in suggestions)
            _SuggestionRow(suggestion: suggestion),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.suggestion});
  final EmptyStateSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (suggestion.onTap != null) {
      return InkWell(
        onTap: suggestion.onTap,
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                AppIcons.addCircleOutline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  suggestion.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\u2022 ',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              suggestion.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
