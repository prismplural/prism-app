import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/emoji/prism_emoji_set.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';
import 'package:prism_plurality/shared/widgets/glass_surface.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

const double _kPickerHeight = 360.0;
const double _kSearchPickerHeight = 124.0;

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
    final hintText = context.l10n.searchEmoji;
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
        hintText: hintText,
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

  static Config _buildConfig(
    ThemeData theme, {
    required String hintText,
    VoidCallback? onSearchOpened,
    VoidCallback? onSearchClosed,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Config(
      height: _kPickerHeight,
      checkPlatformCompatibility: false,
      emojiSet: (_) => prismEmojiSet,
      viewOrderConfig: const ViewOrderConfig(
        top: EmojiPickerItem.searchBar,
        middle: EmojiPickerItem.categoryBar,
        bottom: EmojiPickerItem.emojiView,
      ),
      emojiViewConfig: EmojiViewConfig(
        columns: 8,
        emojiSizeMax:
            28 *
            (foundation.defaultTargetPlatform == TargetPlatform.iOS
                ? 1.2
                : 1.0),
        backgroundColor: Colors.transparent,
        buttonMode: ButtonMode.CUPERTINO,
      ),
      categoryViewConfig: CategoryViewConfig(
        initCategory: Category.SMILEYS,
        extraTab: CategoryExtraTab.SEARCH,
        backgroundColor: Colors.transparent,
        indicatorColor: theme.colorScheme.primary,
        iconColor: theme.colorScheme.onSurfaceVariant,
        iconColorSelected: theme.colorScheme.primary,
        backspaceColor: theme.colorScheme.onSurfaceVariant,
        dividerColor: isDark
            ? AppColors.warmWhite.withValues(alpha: 0.06)
            : AppColors.warmBlack.withValues(alpha: 0.06),
      ),
      bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
      searchViewConfig: SearchViewConfig(
        backgroundColor: Colors.transparent,
        buttonIconColor: theme.colorScheme.onSurfaceVariant,
        hintText: hintText,
        inputTextStyle: theme.textTheme.bodyMedium,
        hintTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        customSearchView: (config, state, showEmojiView) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onSearchOpened?.call();
          });
          return _PrismSearchView(config, state, () {
            onSearchClosed?.call();
            showEmojiView();
          });
        },
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

    return Semantics(
      button: true,
      label: context.l10n.onboardingAddMemberFieldEmoji,
      child: GestureDetector(
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
      ),
    );
  }
}

class _PrismSearchView extends SearchView {
  const _PrismSearchView(super.config, super.state, super.showEmojiView);

  @override
  State<_PrismSearchView> createState() => _PrismSearchViewState();
}

class _PrismSearchViewState extends SearchViewState<_PrismSearchView> {
  @override
  void onTextInputChanged(String text) {
    links.clear();
    results.clear();
    utils
        .searchEmoji(
          text,
          widget.state.categoryEmoji,
          checkPlatformCompatibility: false,
        )
        .then((value) {
          if (!mounted) return;
          setState(() {
            results
              ..clear()
              ..addAll(value);
            for (final result in results) {
              links[result.emoji] = LayerLink();
            }
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final emojiSize = widget.config.emojiViewConfig.getEmojiSize(
          constraints.maxWidth,
        );
        final emojiBoxSize = widget.config.emojiViewConfig.getEmojiBoxSize(
          constraints.maxWidth,
        );
        final resultEmojiSize = emojiSize.clamp(0.0, 32.0).toDouble();
        final resultEmojiBoxSize = emojiBoxSize.clamp(40.0, 48.0).toDouble();

        return Container(
          color: widget.config.searchViewConfig.backgroundColor,
          child: SizedBox(
            height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    height: resultEmojiBoxSize + 4.0,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      scrollDirection: Axis.horizontal,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        return buildEmoji(
                          results[index],
                          resultEmojiSize,
                          resultEmojiBoxSize,
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 12, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: widget.showEmojiView,
                        color: widget.config.searchViewConfig.buttonIconColor,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: TextField(
                          onChanged: onTextInputChanged,
                          focusNode: focusNode,
                          style: widget.config.searchViewConfig.inputTextStyle,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: widget.config.searchViewConfig.hintText,
                            hintStyle:
                                widget.config.searchViewConfig.hintTextStyle,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The picker sheet body wrapped in a tinted glass surface.
class _PickerBody extends StatefulWidget {
  const _PickerBody({
    required this.theme,
    required this.hintText,
    required this.onSelected,
  });

  final ThemeData theme;
  final String hintText;
  final ValueChanged<String> onSelected;

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  bool _isSearching = false;

  void _setSearching(bool value) {
    if (_isSearching == value || !mounted) return;
    setState(() => _isSearching = value);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = modalBottomInsetOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: GlassSurface(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          height: _isSearching ? _kSearchPickerHeight : _kPickerHeight,
          child: EmojiPicker(
            onEmojiSelected: (category, emoji) =>
                widget.onSelected(emoji.emoji),
            config: PrismEmojiPicker._buildConfig(
              widget.theme,
              hintText: widget.hintText,
              onSearchOpened: () => _setSearching(true),
              onSearchClosed: () => _setSearching(false),
            ),
          ),
        ),
      ),
    );
  }
}
