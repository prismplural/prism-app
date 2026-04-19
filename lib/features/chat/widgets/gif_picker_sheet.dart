import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/chat/widgets/gif_preview_overlay.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// A full-screen bottom sheet for browsing and selecting GIFs via the Klipy API.
class GifPickerSheet extends ConsumerStatefulWidget {
  const GifPickerSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  /// Show the GIF picker and return the selected [KlipyGif], or null if
  /// dismissed.
  static Future<KlipyGif?> show(BuildContext context) {
    return PrismSheet.showFullScreen<KlipyGif>(
      context: context,
      builder: (context, scrollController) =>
          GifPickerSheet(scrollController: scrollController),
    );
  }

  @override
  ConsumerState<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends ConsumerState<GifPickerSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  int? _lastAnnouncedCount;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(gifSearchQueryProvider.notifier).set(value.trim());
    });
  }

  Future<void> _onGifTap(KlipyGif gif) async {
    final result = await GifPreviewOverlay.show(context, gif);
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resultsAsync = ref.watch(gifSearchResultsProvider);

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(title: context.l10n.chatGifsTitle),
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TintedGlassSurface(
              borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  icon: Icon(
                    AppIcons.search,
                    size: 20,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  hintText: context.l10n.chatGifsSearchHint,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                textInputAction: TextInputAction.search,
              ),
            ),
          ),
          // Attribution
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.l10n.chatGifsPoweredBy,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          // Results
          Expanded(
            child: resultsAsync.when(
              loading: () => const PrismLoadingState(),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AppIcons.errorOutline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.chatGifsLoadFailed,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      PrismButton(
                        label: context.l10n.tryAgain,
                        icon: AppIcons.refresh,
                        tone: PrismButtonTone.filled,
                        onPressed: () =>
                            ref.invalidate(gifSearchResultsProvider),
                      ),
                    ],
                  ),
                ),
              ),
              data: (gifs) {
                // Announce results for screen readers (only on change).
                if (gifs.length != _lastAnnouncedCount) {
                  _lastAnnouncedCount = gifs.length;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    // ignore: deprecated_member_use
                    SemanticsService.announce(
                      context.l10n.chatGifsFound(gifs.length),
                      TextDirection.ltr,
                    );
                  });
                }

                if (gifs.isEmpty) {
                  return EmptyState(
                    icon: Icon(AppIcons.search),
                    title: context.l10n.chatGifsNotFound,
                    subtitle: context.l10n.chatGifsNotFoundSubtitle,
                  );
                }

                return MasonryGridView.count(
                  controller: widget.scrollController,
                  crossAxisCount: 2,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: gifs.length,
                  itemBuilder: (context, index) {
                    final gif = gifs[index];
                    return _GifCell(
                      gif: gif,
                      onTap: () => _onGifTap(gif),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A single GIF cell in the masonry grid.
class _GifCell extends StatelessWidget {
  const _GifCell({required this.gif, required this.onTap});

  final KlipyGif gif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholderColor = theme.colorScheme.surfaceContainerHighest;

    // Compute aspect ratio from API dimensions, with a sane fallback.
    final double aspectRatio =
        (gif.width > 0 && gif.height > 0) ? gif.width / gif.height : 1.0;

    return Semantics(
      label: gif.contentDescription.isNotEmpty
          ? context.l10n.chatGifCellSemantics(gif.contentDescription)
          : context.l10n.chatGifCellSemanticsDefault,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Image.network(
                gif.previewUrl,
                fit: BoxFit.cover,
                semanticLabel: gif.contentDescription,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) return child;
                  return Container(color: placeholderColor);
                },
                errorBuilder: (context, error, stack) => Container(
                  color: placeholderColor,
                  child: Center(
                    child: Icon(
                      AppIcons.imageBroken,
                      size: 24,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
