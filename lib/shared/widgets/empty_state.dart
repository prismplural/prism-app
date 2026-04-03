import 'package:flutter/material.dart';
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
  const EmptyStateSuggestion({
    required this.text,
    this.onTap,
  });

  final String text;
  final VoidCallback? onTap;
}

/// Generic reusable empty state widget.
///
/// Displays a centered column with a large muted icon in a colored circle,
/// title text, subtitle text, optional suggestions box, and an optional
/// action button. Used across the app to provide consistent empty-state
/// messaging.
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
    final color = iconColor ?? theme.colorScheme.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon in colored circle
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
              ),
              alignment: Alignment.center,
              child: IconTheme(
                data: IconThemeData(size: 48, color: color),
                child: icon,
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Message
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),

            // Suggestions
            if (suggestions != null && suggestions!.isNotEmpty) ...[
              const SizedBox(height: 20),
              _SuggestionsBox(suggestions: suggestions!),
            ],

            // Action button
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suggestions:',
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
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.add_circle_outline,
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
