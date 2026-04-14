import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_checkbox_row.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Bottom sheet for creating a new conversation (DM or group).
///
/// Use via [PrismSheet.showFullScreen] — pass the [scrollController] from the
/// builder callback.
class CreateConversationSheet extends ConsumerStatefulWidget {
  const CreateConversationSheet({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<CreateConversationSheet> createState() =>
      _CreateConversationSheetState();
}

class _CreateConversationSheetState
    extends ConsumerState<CreateConversationSheet> {
  bool _isGroupChat = true;
  final _titleController = TextEditingController();
  final _emojiController = TextEditingController();
  final Set<String> _selectedMemberIds = {};
  String? _selectedCategoryId;
  bool _isCreating = false;
  bool _didPreselect = false;

  @override
  void dispose() {
    _titleController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  bool get _canCreate {
    if (_isGroupChat) {
      return _titleController.text.trim().isNotEmpty &&
          _selectedMemberIds.length >= 2;
    } else {
      // DM: current fronter + one selected other member
      final speakingAs = ref.read(speakingAsProvider);
      return speakingAs != null && _selectedMemberIds.length == 1;
    }
  }

  List<String> get _dmParticipants {
    final speakingAs = ref.read(speakingAsProvider);
    if (speakingAs == null) return _selectedMemberIds.toList();
    return {speakingAs, ..._selectedMemberIds}.toList();
  }

  String _currentFronterName(AsyncValue<dynamic> membersAsync) {
    final speakingAs = ref.read(speakingAsProvider);
    if (speakingAs == null) return '...';
    final members = membersAsync.value;
    if (members == null) return '...';
    for (final m in members) {
      if (m.id == speakingAs) return m.name;
    }
    return '...';
  }

  Future<void> _createConversation() async {
    if (!_canCreate || _isCreating) return;

    setState(() => _isCreating = true);

    final speakingAs = ref.read(speakingAsProvider);

    try {
      final conversation = await ref
          .read(chatNotifierProvider.notifier)
          .createGroupConversation(
            title: _isGroupChat ? _titleController.text.trim() : '',
            emoji: _emojiController.text.trim().isNotEmpty
                ? _emojiController.text.trim()
                : null,
            creatorId: speakingAs ?? _selectedMemberIds.first,
            participantIds: _isGroupChat
                ? _selectedMemberIds.toList()
                : _dmParticipants,
            categoryId: _isGroupChat ? _selectedCategoryId : null,
          );

      if (mounted) {
        Haptics.success();
        Navigator.of(context).pop(conversation.id);
      }
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: context.l10n.chatCreateFailed(e));
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(activeMembersProvider);
    final speakingAs = ref.watch(speakingAsProvider);

    // Pre-select the current fronter once members are loaded
    if (!_didPreselect && speakingAs != null && membersAsync.hasValue) {
      _didPreselect = true;
      _selectedMemberIds.add(speakingAs);
    }

    // Show warning if fronter was deselected in group mode
    final fronterDeselected =
        _isGroupChat &&
        speakingAs != null &&
        !_selectedMemberIds.contains(speakingAs);

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: context.l10n.chatCreateTitle,
            trailing: _isCreating
                ? SizedBox(
                    width: PrismTokens.topBarActionSize,
                    height: PrismTokens.topBarActionSize,
                    child: Center(
                      child: PrismSpinner(
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                  )
                : PrismGlassIconButton(
                    icon: AppIcons.check,
                    size: PrismTokens.topBarActionSize,
                    tint: _canCreate ? theme.colorScheme.primary : null,
                    accentIcon: _canCreate,
                    onPressed: _canCreate ? _createConversation : null,
                  ),
          ),
          const SizedBox(height: 8),

          // Scrollable body
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              children: [
                // DM / Group toggle
                PrismSegmentedControl<bool>(
                  segments: [
                    PrismSegment(value: true, label: context.l10n.chatCreateGroupTab),
                    PrismSegment(value: false, label: context.l10n.chatCreateDirectMessageTab),
                  ],
                  selected: _isGroupChat,
                  onChanged: (value) {
                    setState(() {
                      _isGroupChat = value;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Group-specific fields
                if (_isGroupChat) ...[
                  Row(
                    children: [
                      PrismEmojiPicker(
                        emoji: _emojiController.text.trim().isNotEmpty
                            ? _emojiController.text.trim()
                            : null,
                        onSelected: (emoji) {
                          setState(() {
                            _emojiController.text = emoji;
                          });
                        },
                        size: 48,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PrismTextField(
                          controller: _titleController,
                          labelText: context.l10n.chatCreateGroupName,
                          hintText: context.l10n.chatCreateGroupNameHint,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Category picker
                  Builder(
                    builder: (context) {
                      final categoriesAsync = ref.watch(
                        conversationCategoriesProvider,
                      );
                      final categories = categoriesAsync.value ?? [];
                      if (categories.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final noneLabel = context.l10n.chatInfoCategoryNone;
                      final currentName = _selectedCategoryId != null
                          ? categories
                                    .where((c) => c.id == _selectedCategoryId)
                                    .map((c) => c.name)
                                    .firstOrNull ??
                                noneLabel
                          : noneLabel;
                      return Semantics(
                        button: true,
                        label: context.l10n.chatInfoCategorySemantics(currentName),
                        child: PrismListRow(
                          title: Text(context.l10n.chatInfoCategory),
                          subtitle: Text(currentName),
                          trailing: Icon(AppIcons.chevronRightRounded),
                          onTap: () {
                            PrismSheet.show(
                              context: context,
                              builder: (ctx) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PrismListRow(
                                    title: Text(ctx.l10n.chatInfoCategoryNone),
                                    trailing: _selectedCategoryId == null
                                        ? Icon(AppIcons.checkRounded)
                                        : null,
                                    onTap: () {
                                      setState(
                                        () => _selectedCategoryId = null,
                                      );
                                      Navigator.of(ctx).pop();
                                    },
                                  ),
                                  for (final cat in categories)
                                    PrismListRow(
                                      title: Text(cat.name),
                                      trailing: cat.id == _selectedCategoryId
                                          ? Icon(AppIcons.checkRounded)
                                          : null,
                                      onTap: () {
                                        setState(
                                          () => _selectedCategoryId = cat.id,
                                        );
                                        Navigator.of(ctx).pop();
                                      },
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Member selection header
                Row(
                  children: [
                    Text(
                      _isGroupChat
                          ? context.l10n.chatCreateSelectParticipants
                          : context.l10n.chatCreateMessageAs(_currentFronterName(membersAsync)),
                      style: theme.textTheme.titleSmall,
                    ),
                    const Spacer(),
                    if (_isGroupChat)
                      membersAsync.whenOrNull(
                            data: (members) {
                              if (members.isEmpty) return null;
                              final allSelected = members.every(
                                (m) => _selectedMemberIds.contains(m.id),
                              );
                              return PrismButton(
                                label: allSelected
                                    ? context.l10n.chatCreateDeselectAll
                                    : context.l10n.chatCreateSelectAll,
                                tone: PrismButtonTone.subtle,
                                onPressed: () {
                                  setState(() {
                                    if (allSelected) {
                                      _selectedMemberIds.clear();
                                    } else {
                                      _selectedMemberIds.addAll(
                                        members.map((m) => m.id),
                                      );
                                    }
                                  });
                                },
                              );
                            },
                          ) ??
                          const SizedBox.shrink(),
                  ],
                ),
                const SizedBox(height: 8),

                // Members inline
                membersAsync.when(
                  data: (members) {
                    if (members.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          context.l10n.chatCreateNoMembers,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }

                    final speakingAs = ref.watch(speakingAsProvider);
                    final displayMembers = _isGroupChat
                        ? members
                        : members.where((m) => m.id != speakingAs).toList();

                    return Column(
                      children: [
                        for (final member in displayMembers)
                          PrismCheckboxRow(
                            padding: EdgeInsets.zero,
                            leading: MemberAvatar(
                              avatarImageData: member.avatarImageData,
                              memberName: member.name,
                              emoji: member.emoji,
                              customColorEnabled: member.customColorEnabled,
                              customColorHex: member.customColorHex,
                              size: 36,
                            ),
                            title: Row(
                              children: [
                                Text(member.name),
                                if (member.id == speakingAs) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      context.l10n.chatCreateFronting,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            value: _selectedMemberIds.contains(member.id),
                            onChanged: (selected) {
                              setState(() {
                                if (selected) {
                                  if (!_isGroupChat) _selectedMemberIds.clear();
                                  _selectedMemberIds.add(member.id);
                                } else {
                                  _selectedMemberIds.remove(member.id);
                                }
                              });
                            },
                          ),
                      ],
                    );
                  },
                  loading: () => const PrismLoadingState(),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      context.l10n.chatAddMembersFailed(error),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),

                // Warning when fronter is deselected
                if (fronterDeselected) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          AppIcons.infoOutline,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.chatCreateFronterDeselectedWarning(_currentFronterName(membersAsync)),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
