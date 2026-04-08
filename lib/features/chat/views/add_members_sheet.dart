import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_checkbox_row.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Modal bottom sheet for adding members to an existing conversation.
///
/// Use via [AddMembersSheet.show] — pass the [scrollController] from the
/// builder callback.
class AddMembersSheet extends ConsumerStatefulWidget {
  const AddMembersSheet({
    super.key,
    required this.conversation,
    required this.scrollController,
  });

  final Conversation conversation;
  final ScrollController scrollController;

  /// Show the Add Members sheet using [PrismSheet.showFullScreen].
  static Future<bool?> show(BuildContext context, Conversation conversation) {
    return PrismSheet.showFullScreen<bool>(
      context: context,
      builder: (context, scrollController) => AddMembersSheet(
        conversation: conversation,
        scrollController: scrollController,
      ),
    );
  }

  @override
  ConsumerState<AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends ConsumerState<AddMembersSheet> {
  final Set<String> _selectedIds = {};
  bool _isAdding = false;

  bool get _canAdd => _selectedIds.isNotEmpty && !_isAdding;

  Future<void> _addMembers() async {
    if (!_canAdd) return;
    setState(() => _isAdding = true);

    try {
      // Resolve the speaking-as member name for system messages.
      final speakingAs = ref.read(speakingAsProvider);
      String? speakingAsName;
      if (speakingAs != null) {
        final members = ref.read(activeMembersProvider).value;
        speakingAsName = members
            ?.where((m) => m.id == speakingAs)
            .map((m) => m.name)
            .firstOrNull;
      }

      await ref
          .read(chatNotifierProvider.notifier)
          .addParticipants(
            widget.conversation.id,
            _selectedIds.toList(),
            addedByName: speakingAsName,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: 'Failed to add members: $e');
        setState(() => _isAdding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(activeMembersProvider);
    final existingIds = widget.conversation.participantIds.toSet();

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: 'Add Members',
            trailing: _isAdding
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
                    tint: _canAdd ? theme.colorScheme.primary : null,
                    accentIcon: _canAdd,
                    onPressed: _canAdd ? _addMembers : null,
                  ),
          ),
          const SizedBox(height: 8),

          // Scrollable member list
          Expanded(
            child: membersAsync.when(
              data: (members) {
                final available = members
                    .where((m) => !existingIds.contains(m.id))
                    .toList();

                if (available.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'All active members are already in this conversation.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: widget.scrollController,
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  itemCount: available.length,
                  itemBuilder: (context, index) {
                    final member = available[index];
                    final isSelected = _selectedIds.contains(member.id);

                    return PrismCheckboxRow(
                      padding: EdgeInsets.zero,
                      leading: MemberAvatar(
                        avatarImageData: member.avatarImageData,
                        emoji: member.emoji,
                        customColorEnabled: member.customColorEnabled,
                        customColorHex: member.customColorHex,
                        size: 36,
                      ),
                      title: Text(member.name),
                      subtitle: member.pronouns != null
                          ? Text(member.pronouns!)
                          : null,
                      value: isSelected,
                      onChanged: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedIds.add(member.id);
                          } else {
                            _selectedIds.remove(member.id);
                          }
                        });
                      },
                    );
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: PrismLoadingState(),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error loading members: $error',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
