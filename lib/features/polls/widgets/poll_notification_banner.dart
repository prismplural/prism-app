import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// A small banner widget showing how many polls need attention.
///
/// Displays "X polls need your vote" with a tappable surface.
/// The caller handles navigation via [onTap].
class PollNotificationBanner extends StatelessWidget {
  const PollNotificationBanner({
    super.key,
    required this.count,
    this.onTap,
  });

  /// Number of polls that need the user's vote.
  final int count;

  /// Called when the banner is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return PrismSurface(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      fillColor: theme.colorScheme.primaryContainer,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            AppIcons.howToVote,
            color: theme.colorScheme.onPrimaryContainer,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.pollsNotificationBanner(count),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(
            AppIcons.chevronRight,
            color: theme.colorScheme.onPrimaryContainer,
            size: 20,
          ),
        ],
      ),
    );
  }
}
