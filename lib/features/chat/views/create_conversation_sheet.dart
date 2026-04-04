import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
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
        PrismToast.error(context, message: 'Failed to create conversation: $e');
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
    final fronterDeselected = _isGroupChat &&
        speakingAs != null &&
        !_selectedMemberIds.contains(speakingAs);

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
                title: 'New Conversation',
                trailing: _isCreating
                    ? SizedBox(
                        width: PrismTokens.topBarActionSize,
                        height: PrismTokens.topBarActionSize,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      )
                    : PrismGlassIconButton(
                        icon: AppIcons.check,
                        size: PrismTokens.topBarActionSize,
                        tint: _canCreate
                            ? theme.colorScheme.primary
                            : null,
                        accentIcon: _canCreate,
                        onPressed:
                            _canCreate ? _createConversation : null,
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
                        const PrismSegment(value: true, label: 'Group'),
                        const PrismSegment(value: false, label: 'Direct Message'),
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
                              labelText: 'Group Name',
                              hintText: 'e.g., System Discussion',
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Category picker
                      Builder(
                        builder: (context) {
                          final categoriesAsync =
                              ref.watch(conversationCategoriesProvider);
                          final categories = categoriesAsync.value ?? [];
                          if (categories.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final currentName = _selectedCategoryId != null
                              ? categories
                                  .where((c) => c.id == _selectedCategoryId)
                                  .map((c) => c.name)
                                  .firstOrNull ??
                                'None'
                              : 'None';
                          return Semantics(
                            button: true,
                            label: 'Category: $currentName',
                            child: PrismListRow(
                              title: const Text('Category'),
                              subtitle: Text(currentName),
                              trailing: Icon(AppIcons.chevronRightRounded),
                              onTap: () {
                                PrismSheet.show(
                                  context: context,
                                  builder: (ctx) => Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      PrismListRow(
                                        title: const Text('None'),
                                        trailing: _selectedCategoryId == null
                                            ? Icon(AppIcons.checkRounded)
                                            : null,
                                        onTap: () {
                                          setState(() => _selectedCategoryId = null);
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
                                            setState(() => _selectedCategoryId = cat.id);
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
                              ? 'Select participants (2+)'
                              : 'Message as ${_currentFronterName(membersAsync)} with:',
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
                                    ? 'Deselect All'
                                    : 'Select All',
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
                          ) ?? const SizedBox.shrink(),
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
                              'No members available. Create members first.',
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
                            : members
                                .where((m) => m.id != speakingAs)
                                .toList();

                        return Column(
                          children: [
                            for (final member in displayMembers)
                              PrismListRow(
                                padding: EdgeInsets.zero,
                                leading: MemberAvatar(
                                  avatarImageData: member.avatarImageData,
                                  emoji: member.emoji,
                                  customColorEnabled:
                                      member.customColorEnabled,
                                  customColorHex: member.customColorHex,
                                  size: 36,
                                ),
                                title: Row(
                                  children: [
                                    Text(
                                      member.name,
                                    ),
                                    if (member.id == speakingAs) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme
                                              .colorScheme.primary
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          'Fronting',
                                          style: theme
                                              .textTheme.labelSmall
                                              ?.copyWith(
                                            color: theme
                                                .colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Checkbox(
                                  value: _selectedMemberIds
                                      .contains(member.id),
                                  onChanged: (selected) {
                                    setState(() {
                                      if (selected == true) {
                                        if (!_isGroupChat) {
                                          _selectedMemberIds.clear();
                                        }
                                        _selectedMemberIds.add(member.id);
                                      } else {
                                        _selectedMemberIds
                                            .remove(member.id);
                                      }
                                    });
                                  },
                                ),
                                onTap: () {
                                  setState(() {
                                    if (_selectedMemberIds.contains(member.id)) {
                                      _selectedMemberIds.remove(member.id);
                                    } else {
                                      if (!_isGroupChat) {
                                        _selectedMemberIds.clear();
                                      }
                                      _selectedMemberIds.add(member.id);
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
                          'Error loading members: $error',
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
                          color: theme.colorScheme.errorContainer
                              .withValues(alpha: 0.4),
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
                                '${_currentFronterName(membersAsync)} is currently fronting but not in this chat. You won\'t be able to see or send messages.',
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
