import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/widgets/date_chip.dart';

/// A centered date label for chat message lists.
///
/// Thin wrapper around [DateChip] that adds chat-specific padding.
class DateSeparator extends StatelessWidget {
  const DateSeparator({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: DateChip(date: date),
    );
  }
}
