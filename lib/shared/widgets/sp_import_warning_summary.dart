import 'package:flutter/material.dart';
import 'package:prism_plurality/features/migration/services/sp_import_warning_classifier.dart';

class SpImportWarningSummary extends StatefulWidget {
  const SpImportWarningSummary({
    super.key,
    required this.warnings,
    this.onRetryAvatars,
    this.retryInProgress = false,
  });

  final List<String> warnings;
  final VoidCallback? onRetryAvatars;
  final bool retryInProgress;

  @override
  State<SpImportWarningSummary> createState() => _SpImportWarningSummaryState();
}

class _SpImportWarningSummaryState extends State<SpImportWarningSummary> {
  @override
  Widget build(BuildContext context) {
    final categories = SpImportWarningClassifier.classify(widget.warnings);
    if (categories.isEmpty) return const SizedBox.shrink();
    return const SizedBox.shrink(); // implemented in Task 4
  }
}
