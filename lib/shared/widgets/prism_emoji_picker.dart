import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/emoji/prism_emoji_set.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/icons/phosphor_icon_catalog.dart';
import 'package:prism_plurality/shared/icons/prism_icon_selection.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';
import 'package:prism_plurality/shared/widgets/glass_surface.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

const double _kPickerHeight = 360.0;
const double _kSearchPickerHeight = 124.0;
const double _kPickerTabHeight = 48.0;

// emoji_picker_flutter compares this callback by identity when config changes.
// Keep it stable so keyboard inset rebuilds don't reset the search field.
List<CategoryEmoji> _prismEmojiSetForLocale(Locale _) => prismEmojiSet;

/// A tappable glass circle for selecting either an emoji or a Phosphor icon.
///
/// The default [mode] is emoji-only so existing picker surfaces do not gain new
/// icon UI until they explicitly opt in.
class PrismIconPicker extends StatelessWidget {
  const PrismIconPicker({
    super.key,
    this.selection,
    required this.onSelected,
    this.onCleared,
    this.mode = PrismIconPickerMode.emoji,
    this.size = 48,
    this.semanticLabel,
    this.clearTooltip,
  });

  final PrismIconSelection? selection;
  final ValueChanged<PrismIconSelection> onSelected;
  final VoidCallback? onCleared;
  final PrismIconPickerMode mode;
  final double size;
  final String? semanticLabel;
  final String? clearTooltip;

  static Future<PrismIconSelection?> showPicker(
    BuildContext context, {
    PrismIconPickerMode mode = PrismIconPickerMode.emoji,
    PrismIconSelection? selection,
  }) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final completer = Completer<PrismIconSelection?>();

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
        mode: mode,
        selection: selection,
        emojiHintText: l10n.searchEmoji,
        onSelected: (value) {
          Navigator.of(context, rootNavigator: true).pop();
          completer.complete(value);
        },
      ),
    ).then((_) {
      if (!completer.isCompleted) completer.complete(null);
    });

    return completer.future;
  }

  static Config _buildEmojiConfig(
    ThemeData theme, {
    required String hintText,
    VoidCallback? onSearchOpened,
    VoidCallback? onSearchClosed,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Config(
      height: _kPickerHeight,
      checkPlatformCompatibility: false,
      emojiSet: _prismEmojiSetForLocale,
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
        dividerColor: theme.colorScheme.outlineVariant.withValues(
          alpha: isDark ? 0.24 : 0.32,
        ),
      ),
      skinToneConfig: SkinToneConfig(
        dialogBackgroundColor:
            (isDark
                    ? theme.colorScheme.surfaceContainerHigh
                    : theme.colorScheme.surfaceContainer)
                .withValues(alpha: 0.96),
        indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.72),
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
    showPicker(context, mode: mode, selection: selection).then((value) {
      if (value != null) onSelected(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final canClear = selection != null && onCleared != null;
    final label = semanticLabel ?? l10n.pickIcon;
    final clearLabel = clearTooltip ?? l10n.clearIcon;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Tooltip(
            message: label,
            child: Semantics(
              button: true,
              label: label,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _openPicker(context),
                  child: TintedGlassSurface.circle(
                    size: size,
                    child: _SelectionPreview(
                      selection: selection,
                      size: size,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (canClear)
            Positioned(
              right: -4,
              top: -4,
              child: Tooltip(
                message: clearLabel,
                child: Semantics(
                  button: true,
                  label: clearLabel,
                  child: Material(
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onCleared,
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Icon(
                          AppIcons.close,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Backwards-compatible emoji-only wrapper around [PrismIconPicker].
class PrismEmojiPicker extends StatelessWidget {
  const PrismEmojiPicker({
    super.key,
    this.emoji,
    required this.onSelected,
    this.onCleared,
    this.size = 48,
  });

  /// Currently selected emoji, or null to show the `+` placeholder.
  final String? emoji;

  /// Called when the user picks an emoji from the picker.
  final ValueChanged<String> onSelected;

  /// Called when the current emoji is cleared.
  final VoidCallback? onCleared;

  /// Diameter of the glass circle.
  final double size;

  /// Opens the emoji picker bottom sheet directly.
  /// Returns the selected emoji string, or null if dismissed.
  static Future<String?> showPicker(BuildContext context) async {
    final selection = await PrismIconPicker.showPicker(context);
    return selection?.emoji;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selectedEmoji = emoji != null && emoji!.isNotEmpty
        ? PrismIconSelection.emoji(emoji!)
        : null;

    return PrismIconPicker(
      selection: selectedEmoji,
      mode: PrismIconPickerMode.emoji,
      size: size,
      semanticLabel: l10n.onboardingAddMemberFieldEmoji,
      clearTooltip: l10n.clearEmoji,
      onCleared: onCleared,
      onSelected: (selection) {
        final emoji = selection.emoji;
        if (emoji != null) onSelected(emoji);
      },
    );
  }
}

class _SelectionPreview extends StatelessWidget {
  const _SelectionPreview({
    required this.selection,
    required this.size,
    required this.color,
  });

  final PrismIconSelection? selection;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final selection = this.selection;
    if (selection == null) {
      return Icon(AppIcons.add, size: size * 0.45, color: color);
    }

    final emoji = selection.emoji;
    if (emoji != null) {
      return MemberAvatar.centeredEmoji(emoji, fontSize: size * 0.5);
    }

    final iconName = selection.phosphorName;
    return Icon(
      iconName == null
          ? AppIcons.questionMarkRounded
          : PhosphorIconCatalog.iconFor(iconName) ??
                AppIcons.questionMarkRounded,
      size: size * 0.48,
      color: color,
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
    required this.mode,
    required this.selection,
    required this.emojiHintText,
    required this.onSelected,
  });

  final ThemeData theme;
  final PrismIconPickerMode mode;
  final PrismIconSelection? selection;
  final String emojiHintText;
  final ValueChanged<PrismIconSelection> onSelected;

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
    final hasTabs = widget.mode == PrismIconPickerMode.both;
    final height =
        (_isSearching ? _kSearchPickerHeight : _kPickerHeight) +
        (hasTabs ? _kPickerTabHeight : 0);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: GlassSurface(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          height: height,
          child: switch (widget.mode) {
            PrismIconPickerMode.emoji => _buildEmojiPicker(),
            PrismIconPickerMode.icon => _IconSearchPanel(
              selection: widget.selection,
              onSelected: _selectIcon,
            ),
            PrismIconPickerMode.both => _buildTabbedPicker(context),
          },
        ),
      ),
    );
  }

  Widget _buildTabbedPicker(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final initialIndex =
        widget.selection?.kind == PrismIconSelectionKind.phosphor ? 1 : 0;

    return DefaultTabController(
      length: 2,
      initialIndex: initialIndex,
      child: Column(
        children: [
          SizedBox(
            height: _kPickerTabHeight,
            child: TabBar(
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorColor: theme.colorScheme.primary,
              tabs: [
                Tab(text: l10n.iconPickerEmojiTab),
                Tab(text: l10n.iconPickerIconsTab),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildEmojiPicker(),
                _IconSearchPanel(
                  selection: widget.selection,
                  onSelected: _selectIcon,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiPicker() {
    return EmojiPicker(
      onEmojiSelected: (category, emoji) =>
          widget.onSelected(PrismIconSelection.emoji(emoji.emoji)),
      config: PrismIconPicker._buildEmojiConfig(
        widget.theme,
        hintText: widget.emojiHintText,
        onSearchOpened: () => _setSearching(true),
        onSearchClosed: () => _setSearching(false),
      ),
    );
  }

  void _selectIcon(PhosphorIconCatalogEntry entry) {
    widget.onSelected(PrismIconSelection.phosphor(entry.name));
  }
}

class _IconSearchPanel extends StatefulWidget {
  const _IconSearchPanel({required this.selection, required this.onSelected});

  final PrismIconSelection? selection;
  final ValueChanged<PhosphorIconCatalogEntry> onSelected;

  @override
  State<_IconSearchPanel> createState() => _IconSearchPanelState();
}

class _IconSearchPanelState extends State<_IconSearchPanel> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final results = PhosphorIconCatalog.search(_controller.text).toList();
    final selectedName = widget.selection?.phosphorName;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            autofocus:
                widget.selection?.kind == PrismIconSelectionKind.phosphor,
            decoration: InputDecoration(
              hintText: l10n.searchIcons,
              prefixIcon: Icon(AppIcons.search),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.clearIcon,
                      icon: Icon(AppIcons.close),
                      onPressed: _controller.clear,
                    ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.4 : 0.72,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Text(
                    l10n.iconPickerNoResults,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : GridView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: MediaQuery.sizeOf(context).width < 420
                        ? 5
                        : 8,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final entry = results[index];
                    return _IconResultTile(
                      key: ValueKey('phosphor-icon-${entry.name}'),
                      entry: entry,
                      selected: entry.name == selectedName,
                      onSelected: widget.onSelected,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _IconResultTile extends StatelessWidget {
  const _IconResultTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.onSelected,
  });

  final PhosphorIconCatalogEntry entry;
  final bool selected;
  final ValueChanged<PhosphorIconCatalogEntry> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return Tooltip(
      message: entry.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: entry.label,
        child: Material(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.86)
              : colorScheme.surfaceContainerHighest.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.26 : 0.5,
                ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.72)
                  : colorScheme.outlineVariant.withValues(alpha: 0.38),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelected(entry),
            child: Stack(
              children: [
                Center(child: Icon(entry.icon, size: 24, color: foreground)),
                if (selected)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(AppIcons.check, size: 12, color: foreground),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
