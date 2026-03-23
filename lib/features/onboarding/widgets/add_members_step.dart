import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

class AddMembersStep extends ConsumerWidget {
  const AddMembersStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(allMembersProvider);
    final members = membersAsync.value ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Skylar's Defaults button - only when no members exist
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: GestureDetector(
                onTap: () => ref
                    .read(onboardingProvider.notifier)
                    .addDefaultMembers(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.purple.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome,
                          color: Colors.purple.shade200, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        "Skylar's Defaults",
                        style: TextStyle(
                          color: Colors.purple.shade200,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Members list
          Expanded(
            child: members.isEmpty
                ? Center(
                    child: Text(
                      'No members yet.\nTap "Add Member" or use the defaults.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 15,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              // Avatar/Emoji
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      Colors.white.withValues(alpha: 0.15),
                                ),
                                child: member.avatarImageData != null
                                    ? ClipOval(
                                        child: Image.memory(
                                          member.avatarImageData!,
                                          fit: BoxFit.cover,
                                          width: 40,
                                          height: 40,
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          member.emoji,
                                          style:
                                              const TextStyle(fontSize: 20),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              // Name + pronouns
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      member.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (member.pronouns != null &&
                                        member.pronouns!.isNotEmpty)
                                      Text(
                                        member.pronouns!,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.6),
                                          fontSize: 13,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Delete
                              IconButton(
                                icon: Icon(
                                  Icons.close,
                                  color:
                                      Colors.white.withValues(alpha: 0.5),
                                  size: 20,
                                ),
                                onPressed: () {
                                  ref.read(onboardingProvider.notifier).deleteMember(
                                        member.id,
                                      );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Add member button
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _showAddMemberSheet(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Add Member',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddMemberSheet(BuildContext context, WidgetRef ref) {
    PrismSheet.showFullScreen(
      context: context,
      useRootNavigator: true,
      builder: (ctx, sc) => _AddMemberSheet(scrollController: sc),
    );
  }
}

class _AddMemberSheet extends ConsumerStatefulWidget {
  const _AddMemberSheet({this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  final _nameController = TextEditingController();
  final _pronounsController = TextEditingController();
  final _emojiController = TextEditingController(text: '\u{1F464}');
  final _ageController = TextEditingController();
  final _bioController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _pronounsController.dispose();
    _emojiController.dispose();
    _ageController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PrismSheetTopBar(title: 'Add Member'),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Emoji
                _buildField('Emoji', _emojiController,
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),

                // Name (required)
                _buildField('Name *', _nameController, autofocus: true),
                const SizedBox(height: 12),

                // Pronouns quick-select
                Row(
                  children: [
                    _PronounChip(
                      label: 'She/Her',
                      onTap: () => setState(
                          () => _pronounsController.text = 'she/her'),
                      selected: _pronounsController.text == 'she/her',
                    ),
                    const SizedBox(width: 8),
                    _PronounChip(
                      label: 'He/Him',
                      onTap: () => setState(
                          () => _pronounsController.text = 'he/him'),
                      selected: _pronounsController.text == 'he/him',
                    ),
                    const SizedBox(width: 8),
                    _PronounChip(
                      label: 'They/Them',
                      onTap: () => setState(
                          () => _pronounsController.text = 'they/them'),
                      selected: _pronounsController.text == 'they/them',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildField('Pronouns (custom)', _pronounsController),
                const SizedBox(height: 12),

                // Age (optional)
                _buildField('Age (optional)', _ageController,
                    keyboardType: TextInputType.number),
                const SizedBox(height: 12),

                // Bio (optional)
                _buildField('Bio (optional)', _bioController, maxLines: 3),
                const SizedBox(height: 20),

                // Save button
                GestureDetector(
                  onTap: _save,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Add',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    String hint,
    TextEditingController controller, {
    bool autofocus = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.start,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: keyboardType,
        maxLines: maxLines,
        textAlign: textAlign,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    await ref.read(onboardingProvider.notifier).createMember(
          name: name,
          pronouns: _pronounsController.text.trim().isNotEmpty
              ? _pronounsController.text.trim()
              : null,
          emoji: _emojiController.text.trim().isNotEmpty
              ? _emojiController.text.trim()
              : '\u{1F464}',
          age: int.tryParse(_ageController.text.trim()),
          bio: _bioController.text.trim().isNotEmpty
              ? _bioController.text.trim()
              : null,
        );

    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

class _PronounChip extends StatelessWidget {
  const _PronounChip({
    required this.label,
    required this.onTap,
    required this.selected,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.cyan.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.cyan : Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
