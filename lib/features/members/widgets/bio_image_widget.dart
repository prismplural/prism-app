import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/chat/providers/media_state_providers.dart';
import 'package:prism_plurality/features/chat/widgets/media/image_viewer.dart';
import 'package:prism_plurality/features/members/services/bio_image_size.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';

/// Renders an encrypted bio image inline in a member profile.
///
/// Handles the full lifecycle: blurhash placeholder while the encrypted file is
/// being fetched and decrypted, the loaded image (tappable to open
/// [ImageViewer]), an error state with retry, and an expired state when the
/// relay no longer holds the file.
class BioImageWidget extends ConsumerWidget {
  const BioImageWidget({
    super.key,
    required this.mediaId,
    required this.encryptionKeyB64,
    required this.ciphertextHash,
    required this.plaintextHash,
    required this.blurhash,
    required this.width,
    required this.height,
    required this.memberName,
    this.altText,
    this.size = BioImageSize.unset,
    this.overrideBytes,
    this.maxContentWidth,
  });

  final String mediaId;
  final String encryptionKeyB64;
  final String ciphertextHash;
  final String plaintextHash;
  final String blurhash;
  final int width;
  final int height;
  final String? altText;
  final String memberName;

  /// Author-specified sizing from the markdown URL fragment (`#WxH`, `#50%`…).
  final BioImageSize size;

  /// When set, render these bytes directly instead of fetching/decrypting.
  /// Used for staged (uncommitted) images during editing.
  final Uint8List? overrideBytes;

  /// The content width to resolve percent (`#50%`) sizing against, supplied by
  /// the host (e.g. [PrismMarkdownText] measures it with a LayoutBuilder).
  /// Needed because these images render inline (as `WidgetSpan` children),
  /// which receive unbounded width — so the widget's own LayoutBuilder can't
  /// read the container width. Falls back to that LayoutBuilder when null.
  final double? maxContentWidth;

  static const double _maxHeight = 280.0;

  MediaFileParams get _params => (
        mediaId: mediaId,
        encryptionKeyB64: encryptionKeyB64,
        ciphertextHash: ciphertextHash,
        plaintextHash: plaintextHash,
      );

  double get _aspectRatio =>
      (width > 0 && height > 0) ? width / height : 16.0 / 9.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Percentage width needs the available width. Prefer the host-supplied
    // content width (inline images get unbounded width, so our own
    // LayoutBuilder would read infinity and fall back to a fixed 280).
    if (size.widthFraction != null) {
      final hosted = maxContentWidth;
      if (hosted != null && hosted.isFinite) {
        final w = hosted * size.widthFraction!;
        return _sized(ref, w, w / _aspectRatio, BoxFit.contain);
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth.isFinite
              ? constraints.maxWidth * size.widthFraction!
              : 280.0;
          return _sized(ref, w, w / _aspectRatio, BoxFit.contain);
        },
      );
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);

    // Explicit dimensions from the fragment. Use `contain` (not `fill`) so the
    // image keeps its aspect ratio within the WxH box — `fill` stretches and
    // distorts, which is almost never what an author wants and is inconsistent
    // with Simply Plural's `#WxH` (fit-within) semantics we aim to match.
    if (size.width != null && size.height != null) {
      return _sized(ref, size.width!, size.height!, BoxFit.contain);
    }
    if (size.width != null) {
      final w = size.width!;
      return _sized(ref, w, w / _aspectRatio, BoxFit.contain);
    }
    if (size.height != null) {
      final h = size.height!;
      return _sized(ref, h * _aspectRatio, h, BoxFit.contain);
    }

    // No fragment → default: DPR-scaled intrinsic, capped to _maxHeight.
    final maxW = width > 0 ? (width / dpr) : double.infinity;
    final maxH =
        height > 0 ? (height / dpr).clamp(0.0, _maxHeight) : _maxHeight;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH, maxWidth: maxW),
      child: AspectRatio(
        aspectRatio: _aspectRatio,
        child: _content(ref, BoxFit.contain),
      ),
    );
  }

  Widget _sized(WidgetRef ref, double w, double h, BoxFit fit) {
    return SizedBox(
      width: w,
      height: h,
      child: _content(ref, fit),
    );
  }

  Widget _content(WidgetRef ref, BoxFit fit) {
    // Staged (uncommitted) images render directly from in-memory bytes.
    if (overrideBytes != null) {
      return _LoadedImage(
        bytes: overrideBytes!,
        altText: altText,
        memberName: memberName,
        fit: fit,
      );
    }

    final mediaAsync = ref.watch(mediaFileProvider(_params));
    return mediaAsync.when(
      data: (bytes) {
        if (bytes == null) {
          return _ExpiredPlaceholder(aspectRatio: _aspectRatio);
        }
        return _LoadedImage(
          bytes: bytes,
          altText: altText,
          memberName: memberName,
          fit: fit,
        );
      },
      loading: () => _LoadingPlaceholder(
        blurhash: blurhash,
        aspectRatio: _aspectRatio,
      ),
      error: (err, st) => _ErrorPlaceholder(
        onRetry: () => ref.invalidate(mediaFileProvider(_params)),
      ),
    );
  }
}

// ── Loaded ────────────────────────────────────────────────────────────────────

class _LoadedImage extends StatelessWidget {
  const _LoadedImage({
    required this.bytes,
    required this.memberName,
    this.altText,
    this.fit = BoxFit.contain,
  });

  final Uint8List bytes;
  final String? altText;
  final String memberName;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    // Chat images reuse this widget with an empty [memberName] (there's no
    // single "owner" to attribute the image to), so fall back to a clean
    // generic "Image" rather than the possessive "Image in 's bio". Explicit
    // [altText] always wins when present.
    final label = altText ??
        (memberName.isEmpty
            ? context.l10n.imageSemanticLabel
            : context.l10n.imageSemanticInBio(memberName));
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: () => ImageViewer.show(
          context,
          imageBytes: bytes,
          caption: altText,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).radius(12),
          ),
          // No width/height: the parent passes tight constraints so the image
          // fills its box regardless, and omitting them keeps the max-intrinsic
          // width finite so an IntrinsicColumnWidth table cell can measure it.
          child: Image.memory(
            bytes,
            fit: fit,
            semanticLabel: label,
          ),
        ),
      ),
    );
  }
}

// ── Loading (blurhash or muted placeholder) ───────────────────────────────────

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder({
    required this.blurhash,
    required this.aspectRatio,
  });

  final String blurhash;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: context.l10n.imageSemanticLoading,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(12),
        ),
        child: ExcludeSemantics(
          child: blurhash.isNotEmpty
              ? _BlurhashPlaceholder(blurhash: blurhash)
              : ColoredBox(
                  color: theme.brightness == Brightness.dark
                      ? AppColors.charcoalSurface
                      : AppColors.parchmentElevated,
                  child: const SizedBox.expand(),
                ),
        ),
      ),
    );
  }
}

class _BlurhashPlaceholder extends StatefulWidget {
  const _BlurhashPlaceholder({required this.blurhash});

  final String blurhash;

  @override
  State<_BlurhashPlaceholder> createState() => _BlurhashPlaceholderState();
}

class _BlurhashPlaceholderState extends State<_BlurhashPlaceholder> {
  ui.Image? _decoded;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(_BlurhashPlaceholder old) {
    super.didUpdateWidget(old);
    if (old.blurhash != widget.blurhash) _decode();
  }

  Future<void> _decode() async {
    const pixelW = 32;
    const pixelH = 32;
    try {
      final blurHash = BlurHash.decode(widget.blurhash);
      final rgbaBytes = blurHash.toImage(pixelW, pixelH).getBytes();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgbaBytes,
        pixelW,
        pixelH,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final image = await completer.future;
      if (mounted) setState(() => _decoded = image);
    } catch (_) {
      // BlurHash decode failure — leave blank
    }
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_decoded != null) {
      return RawImage(image: _decoded, fit: BoxFit.cover);
    }
    return const SizedBox.expand();
  }
}

// ── Error ─────────────────────────────────────────────────────────────────────

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = context.l10n.imageSemanticLoadFailed;
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onRetry,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).radius(12),
          ),
          child: ColoredBox(
            color: theme.brightness == Brightness.dark
                ? AppColors.charcoalSurface
                : AppColors.parchmentElevated,
            child: Center(
              // Scale the icon + caption down instead of overflowing a very
              // small cell (e.g. a tiny `#WxH` image).
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppIcons.imageBroken,
                      size: 28,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Expired ───────────────────────────────────────────────────────────────────

class _ExpiredPlaceholder extends StatelessWidget {
  const _ExpiredPlaceholder({required this.aspectRatio});

  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = context.l10n.imageSemanticExpired;
    return Semantics(
      label: label,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(12),
        ),
        child: ColoredBox(
          color: theme.brightness == Brightness.dark
              ? AppColors.charcoalSurface
              : AppColors.parchmentElevated,
          child: Center(
            // Scale down instead of overflowing a tiny cell (see _ErrorPlaceholder).
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.imageOutlined,
                    size: 28,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
