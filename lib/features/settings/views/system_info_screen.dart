import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

class SystemInfoScreen extends ConsumerStatefulWidget {
  const SystemInfoScreen({super.key});

  @override
  ConsumerState<SystemInfoScreen> createState() => _SystemInfoScreenState();
}

class _SystemInfoScreenState extends ConsumerState<SystemInfoScreen> {
  bool _editingSystemName = false;
  bool _editingDescription = false;
  late TextEditingController _systemNameController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _systemNameController = TextEditingController();
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    _systemNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _startEditingName(String? currentName) {
    _systemNameController.text = currentName ?? '';
    setState(() => _editingSystemName = true);
  }

  void _saveSystemName() {
    final name = _systemNameController.text.trim();
    ref
        .read(settingsNotifierProvider.notifier)
        .updateSystemName(name.isEmpty ? null : name);
    setState(() => _editingSystemName = false);
  }

  void _startEditingDescription(String? current) {
    _descriptionController.text = current ?? '';
    setState(() => _editingDescription = true);
  }

  void _saveDescription() {
    final desc = _descriptionController.text.trim();
    ref
        .read(settingsNotifierProvider.notifier)
        .updateSystemDescription(desc.isEmpty ? null : desc);
    setState(() => _editingDescription = false);
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    ref.read(settingsNotifierProvider.notifier).updateSystemAvatarData(bytes);
  }

  Future<void> _removeAvatar() async {
    ref.read(settingsNotifierProvider.notifier).updateSystemAvatarData(null);
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final membersAsync = ref.watch(activeMembersProvider);
    final terms = ref.watch(terminologyProvider);

    return PrismPageScaffold(
      topBar: const PrismTopBar(
        title: 'System Information',
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: settingsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) {
          final members = membersAsync.whenOrNull(data: (m) => m) ?? [];
          final Uint8List? avatarData = settings.systemAvatarData;
          final String? description = settings.systemDescription;
          final theme = Theme.of(context);

          return ListView(
            padding: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: NavBarInset.of(context),
            ),
            children: [
              // Avatar section
              Center(
                child: GestureDetector(
                  onTap: _pickAvatar,
                  onLongPress: avatarData != null
                      ? () {
                          PrismSheet.show(
                            context: context,
                            builder: (ctx) => Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PrismListRow(
                                  leading: Icon(AppIcons.photoLibrary),
                                  title: const Text('Change avatar'),
                                  onTap: () {
                                    Navigator.of(ctx).pop();
                                    _pickAvatar();
                                  },
                                ),
                                PrismListRow(
                                  leading: Icon(
                                    AppIcons.deleteOutline,
                                    color: theme.colorScheme.error,
                                  ),
                                  title: Text(
                                    'Remove avatar',
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.of(ctx).pop();
                                    _removeAvatar();
                                  },
                                ),
                              ],
                            ),
                          );
                        }
                      : null,
                  child: avatarData != null
                      ? CircleAvatar(
                          radius: 56,
                          backgroundImage: MemoryImage(avatarData),
                        )
                      : members.isNotEmpty
                      ? _AvatarCluster(members: members)
                      : CircleAvatar(
                          radius: 56,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            AppIcons.addAPhotoOutlined,
                            size: 32,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // System name
              PrismSectionCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: _editingSystemName
                    ? Row(
                        children: [
                          Expanded(
                            child: PrismTextField(
                              controller: _systemNameController,
                              hintText: 'System name',
                              autofocus: true,
                              onSubmitted: (_) => _saveSystemName(),
                            ),
                          ),
                          const SizedBox(width: 4),
                          PrismInlineIconButton(
                            icon: AppIcons.check,
                            iconSize: 20,
                            tooltip: 'Save system name',
                            onPressed: _saveSystemName,
                          ),
                          PrismInlineIconButton(
                            icon: AppIcons.close,
                            iconSize: 20,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            tooltip: 'Cancel editing',
                            onPressed: () =>
                                setState(() => _editingSystemName = false),
                          ),
                        ],
                      )
                    : GestureDetector(
                        onTap: () => _startEditingName(settings.systemName),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Name',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    settings.systemName ?? 'My System',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              AppIcons.editOutlined,
                              size: 18,
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),

              const SizedBox(height: 12),

              // Description
              PrismSectionCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: _editingDescription
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: PrismTextField(
                              controller: _descriptionController,
                              hintText: 'System description',
                              autofocus: true,
                              maxLines: 3,
                              minLines: 1,
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: (_) => _saveDescription(),
                            ),
                          ),
                          const SizedBox(width: 4),
                          PrismInlineIconButton(
                            icon: AppIcons.check,
                            iconSize: 20,
                            tooltip: 'Save description',
                            onPressed: _saveDescription,
                          ),
                          PrismInlineIconButton(
                            icon: AppIcons.close,
                            iconSize: 20,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            tooltip: 'Cancel editing',
                            onPressed: () =>
                                setState(() => _editingDescription = false),
                          ),
                        ],
                      )
                    : GestureDetector(
                        onTap: () => _startEditingDescription(description),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Description',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    description ?? 'Add a description...',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: description != null
                                          ? theme.colorScheme.onSurface
                                          : theme.colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.5),
                                      fontStyle: description == null
                                          ? FontStyle.italic
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              AppIcons.editOutlined,
                              size: 18,
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),

              const SizedBox(height: 16),

              // Member count
              if (members.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '${members.length} ${members.length == 1 ? terms.singular.toLowerCase() : terms.plural.toLowerCase()}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Circular cluster of member avatars arranged in a ring pattern.
class _AvatarCluster extends StatelessWidget {
  const _AvatarCluster({required this.members});

  final List<dynamic> members;

  static const double _clusterSize = 112;
  static const double _avatarSize = 32;
  static const int _maxVisible = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = members.take(_maxVisible).toList();
    final overflow = members.length - _maxVisible;

    if (visible.length == 1) {
      return MemberAvatar(
        avatarImageData: visible[0].avatarImageData,
        emoji: visible[0].emoji,
        customColorEnabled: visible[0].customColorEnabled,
        customColorHex: visible[0].customColorHex,
        size: _clusterSize,
      );
    }

    final center = visible.first;
    final ring = visible.skip(1).toList();

    return SizedBox(
      width: _clusterSize,
      height: _clusterSize,
      child: Stack(
        children: [
          Positioned(
            left: (_clusterSize - _avatarSize) / 2,
            top: (_clusterSize - _avatarSize) / 2,
            child: MemberAvatar(
              avatarImageData: center.avatarImageData,
              emoji: center.emoji,
              customColorEnabled: center.customColorEnabled,
              customColorHex: center.customColorHex,
              size: _avatarSize,
            ),
          ),
          for (int i = 0; i < ring.length; i++)
            _positionedAvatar(ring[i], i, ring.length, theme),
          if (overflow > 0)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                child: Center(
                  child: Text(
                    '+$overflow',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _positionedAvatar(
    dynamic member,
    int index,
    int total,
    ThemeData theme,
  ) {
    final angle = (index / total) * 2 * math.pi - math.pi / 2;
    const radius = (_clusterSize - _avatarSize) / 2;
    final cx = _clusterSize / 2 + radius * math.cos(angle) - _avatarSize / 2;
    final cy = _clusterSize / 2 + radius * math.sin(angle) - _avatarSize / 2;

    return Positioned(
      left: cx,
      top: cy,
      child: MemberAvatar(
        avatarImageData: member.avatarImageData,
        emoji: member.emoji,
        customColorEnabled: member.customColorEnabled,
        customColorHex: member.customColorHex,
        size: _avatarSize,
      ),
    );
  }
}
