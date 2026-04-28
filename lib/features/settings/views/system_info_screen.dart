import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/avatar_image_picker.dart';

class SystemInfoScreen extends ConsumerStatefulWidget {
  const SystemInfoScreen({super.key});

  @override
  ConsumerState<SystemInfoScreen> createState() => _SystemInfoScreenState();
}

class _SystemInfoScreenState extends ConsumerState<SystemInfoScreen> {
  bool _controllersInitialized = false;
  late TextEditingController _systemNameController;
  late TextEditingController _systemTagController;
  late TextEditingController _descriptionController;
  Timer? _nameSaveDebounce;
  Timer? _tagSaveDebounce;
  Timer? _descriptionSaveDebounce;

  @override
  void initState() {
    super.initState();
    _systemNameController = TextEditingController();
    _systemTagController = TextEditingController();
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    // Flush any pending saves so a navigate-away doesn't lose a recent edit.
    if (_nameSaveDebounce?.isActive ?? false) {
      _nameSaveDebounce!.cancel();
      _saveNameNow();
    }
    if (_tagSaveDebounce?.isActive ?? false) {
      _tagSaveDebounce!.cancel();
      _saveTagNow();
    }
    if (_descriptionSaveDebounce?.isActive ?? false) {
      _descriptionSaveDebounce!.cancel();
      _saveDescriptionNow();
    }
    _systemNameController.dispose();
    _systemTagController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _initControllersFromSettings(
    String? name,
    String? tag,
    String? description,
  ) {
    _systemNameController.text = name ?? '';
    _systemTagController.text = tag ?? '';
    _descriptionController.text = description ?? '';
    _controllersInitialized = true;
  }

  void _scheduleNameSave() {
    _nameSaveDebounce?.cancel();
    _nameSaveDebounce = Timer(const Duration(milliseconds: 300), _saveNameNow);
  }

  void _scheduleTagSave() {
    _tagSaveDebounce?.cancel();
    _tagSaveDebounce = Timer(const Duration(milliseconds: 300), _saveTagNow);
  }

  void _scheduleDescriptionSave() {
    _descriptionSaveDebounce?.cancel();
    _descriptionSaveDebounce = Timer(
      const Duration(milliseconds: 300),
      _saveDescriptionNow,
    );
  }

  void _saveNameNow() {
    _nameSaveDebounce?.cancel();
    final name = _systemNameController.text.trim();
    ref
        .read(settingsNotifierProvider.notifier)
        .updateSystemName(name.isEmpty ? null : name);
  }

  void _saveTagNow() {
    _tagSaveDebounce?.cancel();
    final tag = _systemTagController.text.trim();
    ref
        .read(settingsNotifierProvider.notifier)
        .updateSystemTag(tag.isEmpty ? null : tag);
  }

  void _saveDescriptionNow() {
    _descriptionSaveDebounce?.cancel();
    final desc = _descriptionController.text.trim();
    ref
        .read(settingsNotifierProvider.notifier)
        .updateSystemDescription(desc.isEmpty ? null : desc);
  }

  Future<void> _pickAvatar() async {
    final bytes = await AvatarImagePicker.pickCroppedAvatarBytes(context);
    if (bytes == null) return;

    unawaited(
      ref.read(settingsNotifierProvider.notifier).updateSystemAvatarData(bytes),
    );
  }

  Future<void> _removeAvatar() async {
    unawaited(
      ref.read(settingsNotifierProvider.notifier).updateSystemAvatarData(null),
    );
  }

  void _openColorPicker(BuildContext context, String? currentColorHex) {
    final l10n = context.l10n;
    var pickerColor = currentColorHex != null
        ? AppColors.fromHex(currentColorHex)
        : const Color(0xFFAF8EE9);

    PrismDialog.show(
      context: context,
      title: l10n.systemInfoColorPickAction,
      builder: (dialogContext) {
        return SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) {
              pickerColor = color;
            },
            enableAlpha: false,
            hexInputBar: true,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        );
      },
      actions: [
        PrismButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          label: l10n.cancel,
        ),
        PrismButton(
          onPressed: () {
            Navigator.of(context, rootNavigator: true).pop();
            final hex = (pickerColor.toARGB32() & 0xFFFFFF)
                .toRadixString(16)
                .padLeft(6, '0')
                .toLowerCase();
            ref.read(settingsNotifierProvider.notifier).updateSystemColor(hex);
          },
          label: l10n.systemInfoColorPickAction,
          tone: PrismButtonTone.filled,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final membersAsync = ref.watch(activeMembersProvider);
    final terms = watchTerminology(context, ref);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.systemInfoTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: settingsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text(context.l10n.errorWithDetail(e))),
        data: (settings) {
          if (!_controllersInitialized) {
            _initControllersFromSettings(
              settings.systemName,
              settings.systemTag,
              settings.systemDescription,
            );
          }

          final members = membersAsync.whenOrNull(data: (m) => m) ?? [];
          final Uint8List? avatarData = settings.systemAvatarData;
          final String? colorHex = settings.systemColor;
          final Color? systemColor = colorHex != null
              ? AppColors.fromHex(colorHex)
              : null;
          final theme = Theme.of(context);
          final l10n = context.l10n;

          return ListView(
            padding: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: NavBarInset.of(context),
            ),
            children: [
              // Avatar section — unchanged
              Center(
                child: Semantics(
                  button: true,
                  label: l10n.systemInfoChangeAvatar,
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
                                    title: Text(l10n.systemInfoChangeAvatar),
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
                                      l10n.systemInfoRemoveAvatar,
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
              ),

              const SizedBox(height: 24),

              // System name
              PrismTextField(
                controller: _systemNameController,
                labelText: l10n.systemInfoNameLabel,
                hintText: l10n.systemInfoSystemNameHint,
                onChanged: (_) => _scheduleNameSave(),
                onSubmitted: (_) => _saveNameNow(),
              ),

              const SizedBox(height: 12),

              // System tag
              PrismTextField(
                controller: _systemTagController,
                labelText: l10n.systemInfoTagLabel,
                hintText: l10n.systemInfoTagHint,
                helperText: l10n.systemInfoTagHelper,
                maxLength: 79,
                onChanged: (_) => _scheduleTagSave(),
                onSubmitted: (_) => _saveTagNow(),
              ),

              const SizedBox(height: 12),

              // Description
              PrismTextField(
                controller: _descriptionController,
                labelText: l10n.systemInfoDescriptionLabel,
                hintText: l10n.systemInfoDescriptionHint,
                maxLines: 4,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => _scheduleDescriptionSave(),
                onSubmitted: (_) => _saveDescriptionNow(),
              ),

              const SizedBox(height: 12),

              // System color
              PrismSectionCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.systemInfoColorLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Semantics(
                          label: colorHex != null
                              ? '#$colorHex'
                              : l10n.systemInfoColorNoneSet,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: PrismShapes.of(context).avatarShape(),
                              borderRadius: PrismShapes.of(
                                context,
                              ).avatarBorderRadius(),
                              color:
                                  systemColor ??
                                  theme.colorScheme.surfaceContainerHighest,
                              border: Border.all(
                                color: theme.colorScheme.outline.withValues(
                                  alpha: 0.3,
                                ),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            colorHex != null
                                ? '#$colorHex'
                                : l10n.systemInfoColorNoneSet,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorHex != null
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                              fontStyle: colorHex == null
                                  ? FontStyle.italic
                                  : null,
                            ),
                          ),
                        ),
                        Semantics(
                          button: true,
                          label:
                              l10n.systemInfoColorPickAction +
                              (colorHex != null
                                  ? ', currently #$colorHex'
                                  : ', ${l10n.systemInfoColorNoneSet}'),
                          excludeSemantics: true,
                          child: PrismInlineIconButton(
                            icon: AppIcons.colorize,
                            iconSize: 20,
                            tooltip: l10n.systemInfoColorPickAction,
                            onPressed: () =>
                                _openColorPicker(context, colorHex),
                          ),
                        ),
                        if (colorHex != null) ...[
                          const SizedBox(width: 4),
                          PrismInlineIconButton(
                            icon: AppIcons.close,
                            iconSize: 20,
                            tooltip: l10n.systemInfoColorClearAction,
                            onPressed: () => ref
                                .read(settingsNotifierProvider.notifier)
                                .updateSystemColor(null),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Member count caption
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
                  shape: PrismShapes.of(context).avatarShape(),
                  borderRadius: PrismShapes.of(context).avatarBorderRadius(),
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
