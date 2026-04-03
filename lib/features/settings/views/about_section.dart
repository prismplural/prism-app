import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// About info widget for the settings screen.
///
/// Displays the app icon, name, version, description, and placeholder
/// action links (GitHub, Privacy, Feedback).
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        const SizedBox(height: 8),
        // App icon
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text(
            '\u{1F52E}',
            style: TextStyle(fontSize: 36),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Prism',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Plural system management',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Version 0.1.0',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'A privacy-focused app for managing plural systems. '
            'Track fronting, communicate between headmates, and '
            'keep your system organized.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              avatar: Icon(AppIcons.code, size: 18),
              label: const Text('GitHub'),
              onPressed: () {
                PrismToast.show(context, message: 'GitHub link coming soon');
              },
            ),
            ActionChip(
              avatar: Icon(AppIcons.privacyTipOutlined, size: 18),
              label: const Text('Privacy'),
              onPressed: () {
                PrismToast.show(context, message: 'Privacy policy coming soon');
              },
            ),
            ActionChip(
              avatar: Icon(AppIcons.feedbackOutlined, size: 18),
              label: const Text('Feedback'),
              onPressed: () {
                PrismToast.show(context, message: 'Feedback form coming soon');
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
