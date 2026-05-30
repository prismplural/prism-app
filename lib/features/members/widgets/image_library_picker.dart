import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/features/chat/providers/media_state_providers.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Opens a full-screen picker of the shared encrypted image library and
/// returns the selected image's tag (or null if dismissed / empty library).
///
/// Shared by the bio editor and chat composer so both insert `![](tag)` the
/// same way.
Future<String?> showImageLibraryPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  // Await the first stream emission rather than reading `.value`
  // synchronously — the provider is autoDispose, so from a cold context
  // (e.g. a note editor where nothing was watching it yet) `.value` is null
  // until the stream emits, which would wrongly report an empty library.
  List<MediaAttachment> library;
  try {
    library = await ref.read(imageLibraryProvider.future);
  } catch (_) {
    library = ref.read(imageLibraryProvider).value ?? const [];
  }
  if (!context.mounted) return null;

  if (library.isEmpty) {
    PrismToast.error(context, message: context.l10n.mediaLibraryEmpty);
    return null;
  }

  return PrismSheet.showFullScreen<String>(
    context: context,
    builder: (context, scrollController) => _ImageLibraryPickerSheet(
      library: library,
      scrollController: scrollController,
      onSelect: (tag) => Navigator.of(context).pop(tag),
    ),
  );
}

class _ImageLibraryPickerSheet extends ConsumerWidget {
  const _ImageLibraryPickerSheet({
    required this.library,
    required this.scrollController,
    required this.onSelect,
  });

  final List<MediaAttachment> library;
  final ScrollController scrollController;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Approximate grid cell width (3 columns, 12px outer padding, 8px gutters)
    // so thumbnails decode to ~display size instead of the full 2048px bitmap.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cellWidth = (MediaQuery.of(context).size.width - 24 - 16) / 3;
    final cacheWidth = (cellWidth * dpr).round();

    return Column(
      children: [
        PrismSheetTopBar(title: context.l10n.mediaLibraryPickerTitle),
        Expanded(
          child: GridView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: library.length,
            itemBuilder: (context, index) {
              final img = library[index];
              final params = (
                mediaId: img.mediaId,
                encryptionKeyB64: img.encryptionKeyB64,
                ciphertextHash: img.contentHash,
                plaintextHash: img.plaintextHash,
              );
              final imageAsync = ref.watch(mediaFileProvider(params));

              return GestureDetector(
                onTap: () => onSelect(img.tag),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox.expand(
                          child: imageAsync.when(
                            loading: () => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                            error: (_, __) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(AppIcons.imageBroken,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  size: 20),
                            ),
                            data: (bytes) => bytes != null
                                ? Image.memory(bytes,
                                    fit: BoxFit.cover, cacheWidth: cacheWidth)
                                : Container(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      img.tag,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
