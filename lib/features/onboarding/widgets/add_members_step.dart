import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class AddMembersStep extends ConsumerWidget {
  const AddMembersStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
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
                onTap: () =>
                    ref.read(onboardingProvider.notifier).addDefaultMembers(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(AppIcons.autoAwesome, color: primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.onboardingAddMembersSkylarsDefaults,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: primary,
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
                      context.l10n.onboardingAddMembersNoMembers,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: isDark
                            ? AppColors.mutedTextDark
                            : AppColors.mutedTextLight,
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
                            color: isDark
                                ? AppColors.warmWhite.withValues(alpha: 0.1)
                                : AppColors.parchmentElevated,
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
                                  color: isDark
                                      ? AppColors.warmWhite.withValues(
                                          alpha: 0.15,
                                        )
                                      : AppColors.warmBlack.withValues(
                                          alpha: 0.08,
                                        ),
                                ),
                                child: member.avatarImageData != null
                                    ? ClipOval(
                                        child: Image.memory(
                                          member.avatarImageData!,
                                          fit: BoxFit.cover,
                                          width: 40,
                                          height: 40,
                                          semanticLabel: '${member.name} avatar',
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          member.emoji,
                                          style: const TextStyle(fontSize: 20),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              // Name + pronouns
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      member.name,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        color: isDark
                                            ? AppColors.warmWhite
                                            : AppColors.warmBlack,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (member.pronouns != null &&
                                        member.pronouns!.isNotEmpty)
                                      Text(
                                        member.pronouns!,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: isDark
                                              ? AppColors.mutedTextDark
                                              : AppColors.mutedTextLight,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Delete
                              PrismInlineIconButton(
                                icon: AppIcons.close,
                                color: isDark
                                    ? AppColors.warmWhite.withValues(alpha: 0.7)
                                    : AppColors.warmBlack.withValues(
                                        alpha: 0.7,
                                      ),
                                iconSize: 20,
                                tooltip: context.l10n.onboardingAddMembersRemoveMember,
                                onPressed: () {
                                  ref
                                      .read(onboardingProvider.notifier)
                                      .deleteMember(member.id);
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
                color: isDark
                    ? AppColors.warmWhite.withValues(alpha: 0.15)
                    : AppColors.warmBlack.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? AppColors.warmWhite.withValues(alpha: 0.2)
                      : AppColors.warmBlack.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    AppIcons.add,
                    color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.onboardingAddMembersAddMember,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
                      fontWeight: FontWeight.w600,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    return Column(
      children: [
        PrismSheetTopBar(title: context.l10n.onboardingAddMemberSheetTitle),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Emoji
                _buildField(
                  context.l10n.onboardingAddMemberFieldEmoji,
                  _emojiController,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Name (required)
                _buildField(context.l10n.onboardingAddMemberFieldName, _nameController, autofocus: true),
                const SizedBox(height: 12),

                // Pronouns quick-select
                Row(
                  children: [
                    for (final (label, value) in [
                      (context.l10n.onboardingAddMemberPronounSheHer, 'she/her'),
                      (context.l10n.onboardingAddMemberPronounHeHim, 'he/him'),
                      (context.l10n.onboardingAddMemberPronounTheyThem, 'they/them'),
                    ]) ...[
                      PrismChip(
                        label: label,
                        selected: _pronounsController.text == value,
                        onTap: () =>
                            setState(() => _pronounsController.text = value),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _buildField(context.l10n.onboardingAddMemberFieldPronounsCustom, _pronounsController),
                const SizedBox(height: 12),

                // Age (optional)
                _buildField(
                  context.l10n.onboardingAddMemberFieldAge,
                  _ageController,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),

                // Bio (optional)
                _buildField(context.l10n.onboardingAddMemberFieldBio, _bioController, maxLines: 3),
                const SizedBox(height: 20),

                // Save button
                GestureDetector(
                  onTap: _save,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        context.l10n.onboardingAddMemberSaveButton,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.warmBlack,
                          fontWeight: FontWeight.w600,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.warmWhite.withValues(alpha: 0.1)
            : AppColors.parchmentElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: PrismTextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: keyboardType,
        maxLines: maxLines,
        textAlign: textAlign,
        style: TextStyle(
          color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
        ),
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark
              ? AppColors.warmWhite.withValues(alpha: 0.35)
              : AppColors.warmBlack.withValues(alpha: 0.35),
        ),
        fieldStyle: PrismTextFieldStyle.borderless,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    await ref
        .read(onboardingProvider.notifier)
        .createMember(
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
