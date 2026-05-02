import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/widgets/comments_for_range_section.dart';

/// Comments section shown on session detail screen.
///
/// Thin wrapper around [CommentsForRangeSection] — derives the range from the
/// session's start/end times and delegates all rendering to the range widget.
class SessionCommentsSection extends ConsumerWidget {
  const SessionCommentsSection({super.key, required this.session});

  final FrontingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = DateTimeRange(
      start: session.startTime,
      end: session.endTime ?? session.startTime.add(const Duration(days: 1)),
    );
    return CommentsForRangeSection(
      range: range,
      defaultTargetTime: session.startTime,
    );
  }
}
