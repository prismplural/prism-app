import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/custom_fields/definitions/member_field_definition.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/features/members/navigation/member_navigation_branch.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/views/member_detail_screen.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_editor_scope.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_chip.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

Widget buildMemberEditor(
  BuildContext context,
  CustomField field,
  CustomFieldValue? value,
  String memberId,
) {
  return _MemberFieldEditorWidget(
    field: field,
    memberId: memberId,
    existingValue: value,
  );
}

Widget buildMemberDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return _MemberFieldDisplayWidget(field: field, value: value);
}

Widget buildMemberCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return _MemberFieldDisplayWidget(field: field, value: value, compact: true);
}

class _MemberFieldEditorWidget extends ConsumerStatefulWidget {
  const _MemberFieldEditorWidget({
    required this.field,
    required this.memberId,
    this.existingValue,
  });

  final CustomField field;
  final String memberId;
  final CustomFieldValue? existingValue;

  @override
  ConsumerState<_MemberFieldEditorWidget> createState() =>
      _MemberFieldEditorWidgetState();
}

class _MemberFieldEditorWidgetState
    extends ConsumerState<_MemberFieldEditorWidget>
    with AutomaticKeepAliveClientMixin<_MemberFieldEditorWidget>
    implements PendingFieldEditState {
  late Set<String> _initialIds;
  late Set<String> _currentIds;
  late Map<String, dynamic> _extra;
  CustomFieldsEditorController? _controller;
  bool _keepAlive = false;

  @override
  void initState() {
    super.initState();
    final parsed = _parseValue(widget.existingValue?.value);
    _initialIds = Set<String>.of(parsed.memberIds);
    _currentIds = Set<String>.of(_initialIds);
    _extra = Map<String, dynamic>.of(parsed.extra);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = CustomFieldEditorScope.maybeOf(context);
    if (identical(next, _controller)) return;
    _controller?.unregister(this);
    _controller = next;
    _controller?.register(this);
    _syncDirtyState();
  }

  @override
  void didUpdateWidget(covariant _MemberFieldEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newRaw = widget.existingValue?.value ?? '';
    final oldRaw = oldWidget.existingValue?.value ?? '';
    if (newRaw == oldRaw) return;
    final next = _parseValue(widget.existingValue?.value);
    setState(() {
      _initialIds = Set<String>.of(next.memberIds);
      _currentIds = Set<String>.of(next.memberIds);
      _extra = Map<String, dynamic>.of(next.extra);
    });
    _syncDirtyState();
  }

  @override
  void dispose() {
    _controller?.unregister(this);
    super.dispose();
  }

  @override
  bool get wantKeepAlive => _keepAlive;

  bool get _isDirty => !setEquals(_currentIds, _initialIds);

  @override
  String get fieldId => widget.field.id;

  @override
  String get fieldDisplayName => widget.field.name;

  void _syncDirtyState() {
    final dirty = _isDirty;
    _controller?.markDirty(this, dirty);
    if (_keepAlive == dirty) return;
    _keepAlive = dirty;
    updateKeepAlive();
  }

  void _stage(Set<String> next) {
    if (setEquals(next, _currentIds)) return;
    setState(() => _currentIds = Set<String>.of(next));
    _syncDirtyState();
  }

  void _removeId(String id) {
    if (!_currentIds.contains(id)) return;
    _stage(Set<String>.of(_currentIds)..remove(id));
  }

  Future<void> _openPicker(List<Member> candidates) async {
    final candidateIds = candidates.map((member) => member.id).toSet();
    final selected = await MemberSearchSheet.showMulti(
      context,
      members: candidates,
      termPlural: readTerminology(context, ref).plural,
      initialSelected: _currentIds.intersection(candidateIds),
      allowEmptySelection: true,
    );
    if (selected == null || !mounted) return;
    // Preserve stored references that are intentionally not picker candidates
    // (self/missing/deleted IDs) until the user removes them explicitly.
    final preserved = _currentIds.difference(candidateIds);
    _stage({...preserved, ...selected});
  }

  @override
  Future<void> commitPendingValue() async {
    if (!_isDirty) return;
    final encoded = _encodeValue(_currentIds, _extra);
    final notifier = ref.read(customFieldValueNotifierProvider.notifier);
    Object? failure;
    if (encoded.isEmpty) {
      final existingId = widget.existingValue?.id;
      if (existingId != null) {
        failure = await notifier.deleteValue(existingId);
      }
    } else {
      failure = await notifier.setValue(
        customFieldId: widget.field.id,
        memberId: widget.memberId,
        value: encoded,
        existingId: widget.existingValue?.id,
      );
    }
    if (failure != null) throw failure;
    _initialIds = Set<String>.of(_currentIds);
    _syncDirtyState();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final terms = watchTerminology(context, ref);
    final membersAsync = ref.watch(userVisibleAllMemberListProvider);
    final candidates =
        (membersAsync.value ?? const <Member>[])
            .where(
              (member) => member.id != widget.memberId && !member.isDeleted,
            )
            .toList()
          ..sort(_compareMembersForDisplay);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.field.name,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (_currentIds.isEmpty)
          Text(
            l10n.memberSelectNone,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          _MemberFieldSelectionChips(
            fieldName: widget.field.name,
            ids: _currentIds,
            currentMemberId: widget.memberId,
            compact: false,
            readOnly: false,
            onRemoveId: _removeId,
          ),
        const SizedBox(height: 8),
        PrismButton(
          label: l10n.selectMembers(terms.plural),
          icon: AppIcons.personAdd,
          onPressed: () => _openPicker(candidates),
          enabled: !membersAsync.isLoading,
          density: PrismControlDensity.compact,
          tone: PrismButtonTone.subtle,
        ),
      ],
    );
  }
}

class _MemberFieldDisplayWidget extends StatelessWidget {
  const _MemberFieldDisplayWidget({
    required this.field,
    required this.value,
    this.compact = false,
  });

  final CustomField field;
  final CustomFieldValue value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ids = _parseIds(value.value);
    if (ids.isEmpty) return const SizedBox.shrink();
    return _MemberFieldSelectionChips(
      fieldName: field.name,
      ids: ids,
      currentMemberId: value.memberId,
      compact: compact,
      readOnly: true,
    );
  }
}

class _MemberFieldSelectionChips extends ConsumerWidget {
  const _MemberFieldSelectionChips({
    required this.fieldName,
    required this.ids,
    required this.currentMemberId,
    required this.compact,
    required this.readOnly,
    this.onRemoveId,
  });

  final String fieldName;
  final Set<String> ids;
  final String currentMemberId;
  final bool compact;
  final bool readOnly;
  final ValueChanged<String>? onRemoveId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookupIds = ids.where((id) => id != currentMemberId);
    final membersAsync = ref.watch(
      membersByIdsListProvider(memberIdsKey(lookupIds)),
    );
    final membersById = membersAsync.value ?? const <String, Member>{};
    final resolvedMembers = [
      for (final id in ids)
        if (id != currentMemberId && membersById[id] != null) membersById[id]!,
    ]..sort(_compareMembersForDisplay);
    final resolvedIds = resolvedMembers.map((member) => member.id).toSet();
    final placeholderIds = [
      for (final id in ids)
        if (id == currentMemberId || !resolvedIds.contains(id)) id,
    ];

    final chips = <Widget>[
      for (final member in resolvedMembers)
        _ResolvedMemberChip(
          fieldName: fieldName,
          member: member,
          compact: compact,
          readOnly: readOnly,
          onRemove: onRemoveId == null ? null : () => onRemoveId!(member.id),
        ),
      for (final id in placeholderIds)
        _UnavailableMemberChip(
          fieldName: fieldName,
          selfReference: id == currentMemberId,
          compact: compact,
          onRemove: onRemoveId == null ? null : () => onRemoveId!(id),
        ),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: compact ? 10 : 6,
      runSpacing: compact ? 3 : 4,
      children: chips,
    );
  }
}

class _ResolvedMemberChip extends StatelessWidget {
  const _ResolvedMemberChip({
    required this.fieldName,
    required this.member,
    required this.compact,
    required this.readOnly,
    this.onRemove,
  });

  final String fieldName;
  final Member member;
  final bool compact;
  final bool readOnly;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final remove = onRemove;
    final chip = MemberChip(
      member: member,
      onTap: readOnly ? () => _openMember(context) : null,
      style: compact ? MemberChipStyle.inline : MemberChipStyle.filled,
      avatarSize: compact ? 16 : 20,
      labelMaxLines: 1,
    );
    final semanticLabel = l10n.customFieldMemberSelectedSemantic(
      fieldName,
      member.name,
    );
    final semanticChip = Semantics(label: semanticLabel, child: chip);
    if (remove == null) return semanticChip;
    return _RemovableChipFrame(
      removeLabel: l10n.customFieldMemberRemoveMember(member.name),
      onRemove: remove,
      child: semanticChip,
    );
  }

  void _openMember(BuildContext context) {
    unawaited(
      PrismSheet.showFullScreen<void>(
        context: context,
        builder: (context, _) => MemberDetailScreen(
          memberId: member.id,
          branch: MemberNavigationBranch.members,
        ),
      ),
    );
  }
}

class _UnavailableMemberChip extends StatelessWidget {
  const _UnavailableMemberChip({
    required this.fieldName,
    required this.selfReference,
    required this.compact,
    this.onRemove,
  });

  final String fieldName;
  final bool selfReference;
  final bool compact;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final label = selfReference
        ? l10n.customFieldMemberSelfReference
        : l10n.customFieldMemberUnavailable;
    final textStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    final chip = Opacity(
      opacity: 0.62,
      child: DecoratedBox(
        decoration: compact
            ? const BoxDecoration()
            : BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.4),
                ),
              ),
        child: Padding(
          padding: compact
              ? EdgeInsets.zero
              : const EdgeInsets.fromLTRB(10, 6, 12, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selfReference
                    ? AppIcons.personOutline
                    : AppIcons.personOffOutlined,
                size: compact ? 14 : 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(label, style: textStyle, maxLines: 1),
            ],
          ),
        ),
      ),
    );
    final remove = onRemove;
    final semanticChip = Semantics(
      label: l10n.customFieldMemberChipSemantic(fieldName, label),
      child: chip,
    );
    if (remove == null) return semanticChip;
    return _RemovableChipFrame(
      removeLabel: l10n.customFieldMemberRemoveSelection(label),
      onRemove: remove,
      child: semanticChip,
    );
  }
}

class _RemovableChipFrame extends StatelessWidget {
  const _RemovableChipFrame({
    required this.child,
    required this.removeLabel,
    required this.onRemove,
  });

  final Widget child;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        PrismFieldIconButton(
          icon: AppIcons.clear,
          tooltip: removeLabel,
          semanticLabel: removeLabel,
          onPressed: onRemove,
          size: 28,
          iconSize: 16,
        ),
      ],
    );
  }
}

Set<String> _parseIds(String? raw) {
  return Set<String>.of(_parseValue(raw).memberIds);
}

MemberFieldValue _parseValue(String? raw) {
  final parsed = memberFieldDefinition.valueParser(raw);
  return parsed is MemberFieldValue ? parsed : const MemberFieldValue();
}

String _encodeValue(Set<String> ids, Map<String, dynamic> extra) {
  return memberFieldDefinition.valueEncoder(
    MemberFieldValue(memberIds: ids, extra: extra),
  );
}

int _compareMembersForDisplay(Member a, Member b) {
  final byOrder = a.displayOrder.compareTo(b.displayOrder);
  if (byOrder != 0) return byOrder;
  final byCreatedAt = a.createdAt.compareTo(b.createdAt);
  if (byCreatedAt != 0) return byCreatedAt;
  return a.id.compareTo(b.id);
}
