import 'package:flutter/material.dart';

import 'package:prism_plurality/features/onboarding/models/onboarding_data_counts.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

class OnboardingDataReadyView extends StatelessWidget {
  const OnboardingDataReadyView({
    super.key,
    required this.title,
    required this.description,
    required this.summaryLabel,
    required this.actionLabel,
    required this.onAction,
    this.counts,
    this.notice,
  });

  final String title;
  final String description;
  final String summaryLabel;
  final String actionLabel;
  final VoidCallback onAction;
  final OnboardingDataCounts? counts;
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 56),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          if (notice != null) ...[const SizedBox(height: 12), notice!],
          if (counts != null) ...[
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summaryLabel,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CountRow(label: 'Members', count: counts!.members),
                  _CountRow(
                    label: 'Fronting sessions',
                    count: counts!.frontingSessions,
                  ),
                  _CountRow(
                    label: 'Conversations',
                    count: counts!.conversations,
                  ),
                  _CountRow(label: 'Messages', count: counts!.messages),
                  _CountRow(label: 'Habits', count: counts!.habits),
                  _CountRow(label: 'Notes', count: counts!.notes),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            height: 52,
            child: PrismButton(
              onPressed: onAction,
              label: actionLabel,
              tone: PrismButtonTone.filled,
              expanded: true,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 14,
              ),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
