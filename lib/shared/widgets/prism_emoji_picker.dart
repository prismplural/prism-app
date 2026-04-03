import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/glass_surface.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

const double _kPickerHeight = 360.0;

/// A tappable glass circle that shows the selected emoji or a `+` icon.
/// Tapping opens a themed bottom sheet with the full emoji picker.
class PrismEmojiPicker extends StatelessWidget {
  const PrismEmojiPicker({
    super.key,
    this.emoji,
    required this.onSelected,
    this.size = 48,
  });

  /// Currently selected emoji, or null to show the `+` placeholder.
  final String? emoji;

  /// Called when the user picks an emoji from the picker.
  final ValueChanged<String> onSelected;

  /// Diameter of the glass circle.
  final double size;

  /// Opens the emoji picker bottom sheet directly.
  /// Returns the selected emoji string, or null if dismissed.
  static Future<String?> showPicker(BuildContext context) {
    final theme = Theme.of(context);
    final completer = Completer<String?>();

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PickerBody(
        theme: theme,
        onSelected: (emoji) {
          Navigator.of(context, rootNavigator: true).pop();
          completer.complete(emoji);
        },
      ),
    ).then((_) {
      if (!completer.isCompleted) completer.complete(null);
    });

    return completer.future;
  }

  static Config _buildConfig(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Config(
      height: _kPickerHeight,
      checkPlatformCompatibility: true,
      viewOrderConfig: const ViewOrderConfig(
        top: EmojiPickerItem.searchBar,
        middle: EmojiPickerItem.categoryBar,
        bottom: EmojiPickerItem.emojiView,
      ),
      emojiViewConfig: EmojiViewConfig(
        columns: 8,
        emojiSizeMax: 28 *
            (foundation.defaultTargetPlatform == TargetPlatform.iOS
                ? 1.2
                : 1.0),
        backgroundColor: Colors.transparent,
        buttonMode: ButtonMode.CUPERTINO,
      ),
      categoryViewConfig: CategoryViewConfig(
        initCategory: Category.SMILEYS,
        backgroundColor: Colors.transparent,
        indicatorColor: theme.colorScheme.primary,
        iconColor: theme.colorScheme.onSurfaceVariant,
        iconColorSelected: theme.colorScheme.primary,
        backspaceColor: theme.colorScheme.onSurfaceVariant,
        dividerColor: isDark
            ? AppColors.warmWhite.withValues(alpha: 0.06)
            : AppColors.warmBlack.withValues(alpha: 0.06),
      ),
      bottomActionBarConfig: const BottomActionBarConfig(
        enabled: false,
      ),
      searchViewConfig: SearchViewConfig(
        backgroundColor: Colors.transparent,
        buttonIconColor: theme.colorScheme.onSurfaceVariant,
        hintText: 'Search emoji...',
        inputTextStyle: theme.textTheme.bodyMedium,
        hintTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  void _openPicker(BuildContext context) {
    showPicker(context).then((emoji) {
      if (emoji != null) onSelected(emoji);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasEmoji = emoji != null && emoji!.isNotEmpty;

    return GestureDetector(
      onTap: () => _openPicker(context),
      child: TintedGlassSurface.circle(
        size: size,
        child: hasEmoji
            ? MemberAvatar.centeredEmoji(emoji!, fontSize: size * 0.5)
            : Icon(
                AppIcons.add,
                size: size * 0.45,
                color: theme.colorScheme.onSurfaceVariant,
              ),
      ),
    );
  }
}

/// The picker sheet body wrapped in a tinted glass surface.
class _PickerBody extends StatelessWidget {
  const _PickerBody({
    required this.theme,
    required this.onSelected,
  });

  final ThemeData theme;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: GlassSurface(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        height: _kPickerHeight,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) => onSelected(emoji.emoji),
          config: PrismEmojiPicker._buildConfig(theme),
        ),
      ),
    );
  }
}
