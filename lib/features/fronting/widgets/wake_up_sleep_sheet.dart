import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/utils/member_frequency_sort.dart';
import 'package:prism_plurality/features/fronting/utils/sleep_quality_l10n.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Bottom sheet shown when the user taps "Wake Up" on the sleep mode card.
///
/// Presents a time-aware greeting, the total sleep duration, a star rating
/// for sleep quality, and a morning-weighted quick-front member picker.
class WakeUpSleepSheet extends ConsumerStatefulWidget {
  const WakeUpSleepSheet({super.key, required this.session});

  final FrontingSession session;

  static Future<void> show(BuildContext context, FrontingSession session) {
    return PrismSheet.show(
      context: context,
      isDismissible: false,
      builder: (context) => WakeUpSleepSheet(session: session),
    );
  }

  @override
  ConsumerState<WakeUpSleepSheet> createState() => _WakeUpSleepSheetState();
}

class _WakeUpSleepSheetState extends ConsumerState<WakeUpSleepSheet> {
  SleepQuality _quality = SleepQuality.unknown;
  String? _selectedMemberId;
  bool _saving = false;

  String _greeting(BuildContext context) {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return context.l10n.sleepWakeUpMorning;
    if (hour >= 12 && hour < 17) return context.l10n.sleepWakeUpAfternoon;
    if (hour >= 17 && hour < 21) return context.l10n.sleepWakeUpEvening;
    return context.l10n.sleepWakeUpNight;
  }

  Future<void> _handleDone() async {
    setState(() => _saving = true);
    try {
      final service = ref.read(frontingMutationServiceProvider);
      final result = await service.wakeUp(
        widget.session.id,
        quality: _quality != SleepQuality.unknown ? _quality : null,
        frontingMemberId: _selectedMemberId,
      );
      result.when(
        success: (_) {},
        failure: (failure) => throw failure,
      );
      invalidateFrontingProviders(ref);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) PrismToast.error(context, message: e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleSkip() async {
    setState(() => _saving = true);
    try {
      await ref.read(sleepNotifierProvider.notifier).endSleep(widget.session.id);
      invalidateFrontingProviders(ref);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) PrismToast.error(context, message: e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handlePop(bool didPop, dynamic result) async {
    if (didPop) return;
    await _handleSkip();
  }

  void _showOthersPicker(
    BuildContext context,
    List<Member> allMembers,
    List<Member> topMembers,
  ) {
    final topIds = topMembers.map((m) => m.id).toSet();
    final others = allMembers.where((m) => !topIds.contains(m.id)).toList();

    PrismDialog.show<void>(
      context: context,
      title: context.l10n.sleepWakeUpOthers,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: others
            .map(
              (member) => PrismListRow(
                padding: EdgeInsets.zero,
                leading: Text(
                  member.emoji,
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text(member.name),
                onTap: () {
                  setState(() => _selectedMemberId = member.id);
                  Navigator.of(ctx).pop();
                },
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(activeMembersProvider);
    final morningCountsAsync = ref.watch(morningFrontingCountsProvider);

    final duration = DateTime.now().difference(widget.session.startTime);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handlePop,
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 8,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              _greeting(context),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.sleepWakeUpSleptFor(duration.toShortString()),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Quality section
            Text(
              context.l10n.sleepWakeUpQualityQuestion,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final q in [
                  SleepQuality.veryPoor,
                  SleepQuality.poor,
                  SleepQuality.fair,
                  SleepQuality.good,
                  SleepQuality.excellent,
                ])
                  Semantics(
                    button: true,
                    selected: _quality != SleepQuality.unknown &&
                        _quality.index >= q.index,
                    label: context.l10n
                        .frontingRateSleepAs(q.localizedLabel(context.l10n)),
                    child: IconButton(
                      onPressed: () => setState(() => _quality = q),
                      icon: Icon(
                        (_quality != SleepQuality.unknown &&
                                _quality.index >= q.index)
                            ? AppIcons.starRounded
                            : AppIcons.starOutlineRounded,
                        color: (_quality != SleepQuality.unknown &&
                                _quality.index >= q.index)
                            ? Colors.amber
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.2),
                        size: 28,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      tooltip: q.localizedLabel(context.l10n),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // Member picker section
            Text(
              context.l10n.sleepWakeUpWhosFronting,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final members = membersAsync.value ?? [];
                final morningCounts = morningCountsAsync.value ?? {};
                final topMembers = sortMembersByFrequency(
                  members,
                  morningCounts,
                  take: 4,
                );
                final hasOthers = members.length > 4;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: topMembers.map((member) {
                        final isSelected = _selectedMemberId == member.id;
                        final accentColor = member.customColorEnabled &&
                                member.customColorHex != null
                            ? AppColors.fromHex(member.customColorHex!)
                            : theme.colorScheme.primary;

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Semantics(
                            label: member.name,
                            button: true,
                            selected: isSelected,
                            child: GestureDetector(
                              onTap: () => setState(
                                () => _selectedMemberId =
                                    _selectedMemberId == member.id
                                        ? null
                                        : member.id,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: isSelected
                                        ? BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: accentColor,
                                              width: 3,
                                            ),
                                          )
                                        : null,
                                    child: Center(
                                      child: MemberAvatar(
                                        avatarImageData: member.avatarImageData,
                                        memberName: member.name,
                                        emoji: member.emoji,
                                        customColorEnabled:
                                            member.customColorEnabled,
                                        customColorHex: member.customColorHex,
                                        size: 56,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    width: 64,
                                    child: Text(
                                      member.name,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (hasOthers) ...[
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () =>
                            _showOthersPicker(context, members, topMembers),
                        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(8)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _selectedMemberId != null &&
                                        !topMembers.any(
                                          (m) => m.id == _selectedMemberId,
                                        )
                                    ? (members
                                            .where(
                                              (m) => m.id == _selectedMemberId,
                                            )
                                            .firstOrNull
                                            ?.name ??
                                        context.l10n.sleepWakeUpOthers)
                                    : context.l10n.sleepWakeUpOthers,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              Icon(
                                AppIcons.chevronRightRounded,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: PrismButton(
                    label: context.l10n.sleepWakeUpSkip,
                    onPressed: _handleSkip,
                    enabled: !_saving,
                    tone: PrismButtonTone.subtle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrismButton(
                    label: context.l10n.sleepWakeUpDone,
                    onPressed: _handleDone,
                    enabled: !_saving,
                    isLoading: _saving,
                    tone: PrismButtonTone.filled,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
