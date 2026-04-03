import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Modal for creating a new fronting session with full details.
///
/// Opens via [PrismSheet.showFullScreen] for consistency with other modals.
class AddFrontSessionSheet extends ConsumerStatefulWidget {
  const AddFrontSessionSheet({
    super.key,
    required this.scrollController,
  });

  final ScrollController scrollController;

  /// Opens the sheet using the standard full-screen modal pattern.
  static Future<bool?> show(BuildContext context) {
    return PrismSheet.showFullScreen<bool>(
      context: context,
      builder: (context, scrollController) => AddFrontSessionSheet(
        scrollController: scrollController,
      ),
    );
  }

  @override
  ConsumerState<AddFrontSessionSheet> createState() =>
      _AddFrontSessionSheetState();
}

class _AddFrontSessionSheetState extends ConsumerState<AddFrontSessionSheet>
    with WidgetsBindingObserver {
  static const _unknownId = '__unknown__';
  String? _selectedId; // null = nothing selected, _unknownId = unknown
  final Set<String> _coFronterIds = {};
  FrontConfidence? _confidence;
  final _notesController = TextEditingController();
  final _notesFocus = FocusNode();
  final _notesKey = GlobalKey();
  bool _saving = false;
  bool _coFrontMode = false;

  bool get _frontAsUnknown => _selectedId == _unknownId;
  String? get _selectedMemberId => _frontAsUnknown ? null : _selectedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notesFocus.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Fires on every frame of the keyboard animation. Scroll the focused
    // field into view so it tracks alongside the keyboard.
    if (_notesFocus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _notesKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _addCoFronter(String memberId) async {
    setState(() => _saving = true);
    try {
      final notifier = ref.read(frontingNotifierProvider.notifier);
      await notifier.addCoFronter(memberId);
      Haptics.success();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: 'Error adding co-fronter: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _create() async {
    setState(() => _saving = true);

    try {
      final notifier = ref.read(frontingNotifierProvider.notifier);
      await notifier.startFrontingWithDetails(
        memberId: _frontAsUnknown ? null : _selectedMemberId,
        coFronterIds: _coFronterIds.toList(),
        confidence: _confidence,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );
      Haptics.success();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: 'Error creating session: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(activeMembersProvider);
    final activeSessionsAsync = ref.watch(activeSessionsProvider);
    final activeSessions =
        activeSessionsAsync.whenOrNull(data: (s) => s) ?? [];
    final frontingMemberIds = <String>{
      for (final s in activeSessions) ...[
        if (s.memberId != null) s.memberId!,
        ...s.coFronterIds,
      ],
    };
    final hasActiveSession = activeSessions.isNotEmpty;

    return Column(
      children: [
        PrismSheetTopBar(
          title: _coFrontMode ? 'Add Co-Fronter' : 'New Session',
          trailing: PrismGlassIconButton(
            icon: AppIcons.check,
            onPressed: (_saving || _selectedId == null)
                ? null
                : _coFrontMode
                    ? () => _addCoFronter(_selectedId!)
                    : _create,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: EdgeInsets.fromLTRB(
              24, 24, 24,
              24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            children: [
              // Header row with optional co-front toggle
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _coFrontMode ? 'Select Member' : 'Select Fronter',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (hasActiveSession) ...[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() {
                        _coFrontMode = !_coFrontMode;
                        _selectedId = null;
                        _coFronterIds.clear();
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _coFrontMode
                                ? AppColors.fronting(theme.brightness).withValues(alpha: 0.15)
                                : Colors.transparent,
                            border: Border.all(
                              color: _coFrontMode
                                  ? AppColors.fronting(theme.brightness)
                                  : theme.colorScheme.outline
                                      .withValues(alpha: 0.4),
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                AppIcons.group,
                                size: 14,
                                color: _coFrontMode
                                    ? AppColors.fronting(theme.brightness)
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Co-front',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: _coFrontMode
                                      ? AppColors.fronting(theme.brightness)
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontWeight: _coFrontMode
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              membersAsync.when(
                loading: () => const PrismLoadingState(),
                error: (e, _) => Text('Error: $e'),
                data: (members) => _MemberGrid(
                  members: members,
                  selectedId: _selectedId,
                  unknownId: _unknownId,
                  frontingMemberIds: frontingMemberIds,
                  coFrontMode: _coFrontMode,
                  onSelect: (id) {
                    setState(() {
                      _selectedId = id;
                      if (id == _unknownId) _coFronterIds.clear();
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Co-fronter multi-select (hidden in co-front mode)
              if (_selectedMemberId != null && !_coFrontMode) ...[
                Text(
                  'Co-Fronters',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                membersAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (members) {
                    final available = members
                        .where((m) => m.id != _selectedMemberId)
                        .toList();
                    if (available.isEmpty) {
                      return Text(
                        'No other members available',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    }
                    return Column(
                      children: available.map((m) {
                        return CheckboxListTile(
                          value: _coFronterIds.contains(m.id),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _coFronterIds.add(m.id);
                              } else {
                                _coFronterIds.remove(m.id);
                              }
                            });
                          },
                          title: Text(m.name),
                          secondary: MemberAvatar(
                            avatarImageData: m.avatarImageData,
                            emoji: m.emoji,
                            customColorEnabled: m.customColorEnabled,
                            customColorHex: m.customColorHex,
                            size: 36,
                          ),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],

              if (_coFrontMode) ...[
                // In co-front mode, just show a hint
                Text(
                  'Tap a member to add them as a co-fronter to the current session.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // Confidence level picker (hidden in co-front mode)
              if (!_coFrontMode) ...[
              Text(
                'Confidence Level',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _ConfidencePicker(
                selected: _confidence,
                onSelect: (c) => setState(() => _confidence = c),
              ),
              const SizedBox(height: 24),

              // Notes
              PrismTextField(
                key: _notesKey,
                controller: _notesController,
                focusNode: _notesFocus,
                labelText: 'Notes',
                hintText: 'Optional notes about this session...',
                alignLabelWithHint: true,
                maxLines: 6,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 32),
              ], // end if (!_coFrontMode)
            ],
          ),
        ),
      ],
    );
  }
}

/// Switches between a large grid (≤12 members) and a searchable compact list
/// (>12 members) for selecting the fronting member.
class _MemberGrid extends StatefulWidget {
  const _MemberGrid({
    required this.members,
    required this.selectedId,
    required this.unknownId,
    required this.onSelect,
    this.frontingMemberIds = const {},
    this.coFrontMode = false,
  });

  final List<Member> members;
  final String? selectedId;
  final String unknownId;
  final ValueChanged<String> onSelect;
  final Set<String> frontingMemberIds;
  final bool coFrontMode;

  /// Threshold above which we switch to compact list + search.
  static const int _compactThreshold = 12;

  @override
  State<_MemberGrid> createState() => _MemberGridState();
}

class _MemberGridState extends State<_MemberGrid> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    if (widget.members.length > _MemberGrid._compactThreshold) {
      return _buildCompactList(context);
    }
    return _buildLargeGrid(context);
  }

  // ---------------------------------------------------------------------------
  // Large grid (≤12 members): 3 columns, big avatars
  // ---------------------------------------------------------------------------

  Widget _buildLargeGrid(BuildContext context) {
    final theme = Theme.of(context);
    final showUnknown = !widget.coFrontMode;
    final totalCount = widget.members.length + (showUnknown ? 1 : 0);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
        childAspectRatio: 0.85,
      ),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (showUnknown && index == totalCount - 1) {
          return _gridUnknownTile(theme);
        }
        return _gridMemberTile(theme, widget.members[index]);
      },
    );
  }

  Widget _gridMemberTile(ThemeData theme, Member member) {
    final isSelected = member.id == widget.selectedId;
    final isFronting = widget.frontingMemberIds.contains(member.id);
    // In co-front mode, already-fronting members are not selectable
    final isDisabled = widget.coFrontMode && isFronting;
    return GestureDetector(
      onTap: isDisabled ? null : () => widget.onSelect(member.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: isSelected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
                color: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.3),
              )
            : null,
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Opacity(
              opacity: isFronting && !isSelected ? 0.5 : 1.0,
              child: MemberAvatar(
                avatarImageData: member.avatarImageData,
                emoji: member.emoji,
                customColorEnabled: member.customColorEnabled,
                customColorHex: member.customColorHex,
                size: 72,
                tintOverride: isFronting ? AppColors.fronting(theme.brightness) : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              member.name,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (isFronting) ...[
              const SizedBox(height: 2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.fronting(theme.brightness).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.flashOn, size: 10, color: AppColors.fronting(theme.brightness)),
                    const SizedBox(width: 2),
                    Text(
                      'Fronting',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.fronting(theme.brightness),
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _gridUnknownTile(ThemeData theme) {
    final isSelected = widget.selectedId == widget.unknownId;
    return GestureDetector(
      onTap: () => widget.onSelect(widget.unknownId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: isSelected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
                color: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.3),
              )
            : null,
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Icon(
                AppIcons.questionMarkRounded,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Unknown',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Compact list (>12 members): search bar + scrollable list rows
  // ---------------------------------------------------------------------------

  Widget _buildCompactList(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _search.isEmpty
        ? widget.members
        : widget.members
            .where(
              (m) => m.name.toLowerCase().contains(_search.toLowerCase()),
            )
            .toList();

    return Column(
      children: [
        // Search field
        PrismTextField(
          hintText: 'Search members...',
          prefixIcon: Icon(AppIcons.search, size: 20),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 12),

        // "Unknown" row (hidden in co-front mode)
        if (_search.isEmpty && !widget.coFrontMode) ...[
          _listRow(
            theme: theme,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Icon(
                AppIcons.questionMarkRounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            name: 'Unknown',
            isSelected: widget.selectedId == widget.unknownId,
            onTap: () => widget.onSelect(widget.unknownId),
          ),
          Divider(
            height: 1,
            indent: 56,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ],

        // Member rows
        ...filtered.map((member) {
          final isSelected = member.id == widget.selectedId;
          final isFronting = widget.frontingMemberIds.contains(member.id);
          final isDisabled = widget.coFrontMode && isFronting;
          return _listRow(
            theme: theme,
            leading: MemberAvatar(
              avatarImageData: member.avatarImageData,
              emoji: member.emoji,
              customColorEnabled: member.customColorEnabled,
              customColorHex: member.customColorHex,
              size: 40,
              tintOverride: isFronting ? AppColors.fronting(theme.brightness) : null,
            ),
            name: member.name,
            isSelected: isSelected,
            isFronting: isFronting,
            isDisabled: isDisabled,
            onTap: isDisabled ? null : () => widget.onSelect(member.id),
          );
        }),

        if (filtered.isEmpty && _search.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No members matching "$_search"',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _listRow({
    required ThemeData theme,
    required Widget leading,
    required String name,
    required bool isSelected,
    bool isFronting = false,
    bool isDisabled = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Opacity(
                opacity: isFronting && !isSelected ? 0.5 : 1.0,
                child: leading,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (isFronting && !isSelected)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.fronting(theme.brightness).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.flashOn, size: 10, color: AppColors.fronting(theme.brightness)),
                      const SizedBox(width: 2),
                      Text(
                        'Fronting',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.fronting(theme.brightness),
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              if (isSelected)
                Icon(
                  AppIcons.checkCircle,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfidencePicker extends StatelessWidget {
  const _ConfidencePicker({
    required this.selected,
    required this.onSelect,
  });

  final FrontConfidence? selected;
  final ValueChanged<FrontConfidence?> onSelect;

  static const _labels = {
    FrontConfidence.unsure: 'Unsure',
    FrontConfidence.strong: 'Strong',
    FrontConfidence.certain: 'Certain',
  };

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<FrontConfidence>(
      segments: FrontConfidence.values.map((c) {
        return ButtonSegment<FrontConfidence>(
          value: c,
          label: Text(
            _labels[c]!,
            style: const TextStyle(fontSize: 12),
          ),
        );
      }).toList(),
      selected: selected != null ? {selected!} : {},
      emptySelectionAllowed: true,
      onSelectionChanged: (values) {
        onSelect(values.isEmpty ? null : values.first);
      },
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
