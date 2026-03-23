import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

/// Shown on the fronting screen when no system members exist yet.
class EmptySystemView extends ConsumerWidget {
  const EmptySystemView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final terms = ref.watch(terminologyProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            Text(
              'Welcome to Prism',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first system ${terms.singularLower} to get started',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            PrismButton(
              onPressed: () => _openAddMemberSheet(context),
              icon: Icons.add,
              label: terms.addButtonText,
              tone: PrismButtonTone.filled,
            ),
          ],
        ),
      ),
    );
  }

  void _openAddMemberSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => AddEditMemberSheet(
        scrollController: scrollController,
      ),
    );
  }
}
