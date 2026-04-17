import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/onboarding/widgets/onboarding_data_ready_view.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

/// Priority order for which entity keys to surface first.
const _kPriorityKeys = [
  'members',
  'fronting_sessions',
  'conversations',
  'chat_messages',
  'habits',
  'notes',
];

String _labelForKey(String key, SystemTerminology terminology) {
  switch (key) {
    case 'members':
      switch (terminology) {
        case SystemTerminology.members:
          return 'Members';
        case SystemTerminology.alters:
          return 'Alters';
        case SystemTerminology.parts:
          return 'Parts';
        case SystemTerminology.facets:
          return 'Facets';
        default:
          return 'Headmates';
      }
    case 'fronting_sessions':
      return 'Fronting sessions';
    case 'conversations':
      return 'Conversations';
    case 'chat_messages':
      return 'Messages';
    case 'habits':
      return 'Habits';
    case 'notes':
      return 'Notes';
    default:
      // De-snake_case: "member_groups" → "Member groups"
      final words = key.split('_');
      if (words.isEmpty) return key;
      return '${words.first[0].toUpperCase()}${words.first.substring(1)} ${words.skip(1).join(' ')}'.trim();
  }
}

/// Selects up to 4 entries from [counts] by priority, excluding zero values.
List<MapEntry<String, int>> _pickRows(Map<String, int> counts) {
  final nonZero = Map.fromEntries(
    counts.entries.where((e) => e.value > 0),
  );
  if (nonZero.isEmpty) return [];

  final result = <MapEntry<String, int>>[];

  for (final key in _kPriorityKeys) {
    if (result.length >= 4) break;
    if (nonZero.containsKey(key)) {
      result.add(MapEntry(key, nonZero[key]!));
    }
  }

  // Fill remaining slots with keys not in the priority list (insertion order).
  for (final entry in nonZero.entries) {
    if (result.length >= 4) break;
    if (!_kPriorityKeys.contains(entry.key)) {
      result.add(entry);
    }
  }

  return result;
}

class LiveCountCard extends StatefulWidget {
  final Map<String, int> counts;
  final SystemTerminology terminology;

  const LiveCountCard({
    required this.counts,
    required this.terminology,
    super.key,
  });

  @override
  State<LiveCountCard> createState() => _LiveCountCardState();
}

class _LiveCountCardState extends State<LiveCountCard> {
  // Previous snapshot used to decide whether to tween a value.
  final Map<String, int> _prev = {};
  bool _hasEverMounted = false;

  @override
  void didUpdateWidget(LiveCountCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Snapshot old counts so we can compare deltas in build.
    _prev
      ..clear()
      ..addAll(oldWidget.counts);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _pickRows(widget.counts);

    if (rows.isNotEmpty) {
      _hasEverMounted = true;
    }

    if (!_hasEverMounted) {
      return const SizedBox.shrink();
    }

    final disableAnim = MediaQuery.of(context).disableAnimations;
    final animDuration = disableAnim ? Duration.zero : const Duration(milliseconds: 300);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ExcludeSemantics(
      child: AnimatedSize(
        duration: animDuration,
        curve: Curves.easeOut,
        child: rows.isEmpty
            ? const SizedBox.shrink()
            : Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.warmWhite.withValues(alpha: 0.1)
                      : AppColors.parchmentElevated,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: rows.map((entry) {
                    final key = entry.key;
                    final newVal = entry.value;
                    final prevVal = _prev[key] ?? newVal;
                    final delta = (newVal - prevVal).abs();
                    final shouldTween = delta >= 50 && !disableAnim;
                    final tweenDuration = disableAnim
                        ? Duration.zero
                        : const Duration(milliseconds: 400);
                    final label = _labelForKey(key, widget.terminology);

                    final countWidget = shouldTween
                        ? TweenAnimationBuilder<int>(
                            duration: tweenDuration,
                            tween: IntTween(begin: prevVal, end: newVal),
                            builder: (ctx, v, _) => Text(
                              '$v',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.warmBlack,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : Text(
                            '$newVal',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDark
                                  ? AppColors.warmWhite
                                  : AppColors.warmBlack,
                              fontWeight: FontWeight.w700,
                            ),
                          );

                    return OnboardingCountRow(
                      key: ValueKey(key),
                      label: label,
                      count: newVal,
                      countWidget: countWidget,
                    );
                  }).toList(),
                ),
              ),
      ),
    );
  }
}
