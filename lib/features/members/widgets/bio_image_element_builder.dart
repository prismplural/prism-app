import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/features/members/services/bio_image_processor.dart';
import 'package:prism_plurality/features/members/services/bio_image_size.dart';
import 'package:prism_plurality/features/members/widgets/bio_image_widget.dart';

/// Resolves `img` markdown elements to [BioImageWidget]s against the shared
/// encrypted image library. Receives the raw `src` attribute (with any `#WxH`
/// fragment) so author sizing is preserved.
///
/// Reused across every surface that renders library images (bios, notes,
/// custom fields, group descriptions, chat). Tag refs (`![](nbflag)`) resolve
/// against [library]; legacy `prism-media://<uuid>` refs resolve against
/// [bioMedia] (member-scoped). External URLs and unsafe schemes are dropped.
class BioImageElementBuilder extends MarkdownElementBuilder {
  BioImageElementBuilder({
    required this.library,
    this.bioMedia = const [],
    this.processor,
    this.memberName = '',
    this.contentWidth,
  });

  /// Shared image library (attachments with a non-empty tag).
  final List<MediaAttachment> library;

  /// Member-scoped attachments for legacy `prism-media://` UUID refs.
  final List<MediaAttachment> bioMedia;

  /// Optional processor for staged (uncommitted) image bytes during editing.
  final BioImageProcessor? processor;

  /// Name used in the image's semantics label.
  final String memberName;

  /// Content width that percent (`#50%`) sizing resolves against. Inline images
  /// render as `WidgetSpan` children (unbounded width), so the host measures
  /// the available width and passes it down. Null → BioImageWidget falls back
  /// to its own LayoutBuilder.
  final double? contentWidth;

  @override
  bool isBlockElement() => false; // keep images inline so they flow with text

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final src = element.attributes['src'] ?? '';
    final alt = element.attributes['alt'];
    return _resolve(src, alt?.isNotEmpty == true ? alt : null);
  }

  Widget _resolve(String src, String? alt) {
    if (src.isEmpty) return const SizedBox.shrink();

    final hashIdx = src.indexOf('#');
    final ref = hashIdx >= 0 ? src.substring(0, hashIdx) : src;
    var fragment = hashIdx >= 0 ? src.substring(hashIdx + 1) : null;
    if (fragment != null) {
      // The markdown URL layer percent-encodes `%` in the fragment, so an
      // author's `#50%` arrives here as `50%25`. Decode it back so percentage
      // sizing parses (px/`#WxH` fragments are unaffected). Fall back to the
      // raw fragment if it isn't valid percent-encoding.
      try {
        fragment = Uri.decodeComponent(fragment);
      } catch (_) {}
    }
    final size = BioImageSize.parse(fragment);

    final uri = Uri.tryParse(ref);
    if (uri == null) return const SizedBox.shrink();

    // Block dangerous schemes + external URLs (privacy: viewer never fetches
    // from remote hosts; everything is encrypted + relay-hosted).
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'data' ||
        scheme == 'javascript' ||
        scheme == 'http' ||
        scheme == 'https') {
      return const SizedBox.shrink();
    }

    // Bare tag reference: `![](nbflag)`.
    if (scheme.isEmpty && ref.isNotEmpty) {
      final stagedBytes = processor?.getStagedByTag(ref);
      if (stagedBytes != null) return _staged(stagedBytes, alt, size);
      final attachment = _firstWhere(library, (a) => a.tag == ref);
      if (attachment != null) return _widget(attachment, alt, size);
      return const SizedBox.shrink();
    }

    // Legacy `prism-media://<mediaId>`.
    if (scheme == 'prism-media') {
      final mediaId = uri.host.isNotEmpty
          ? uri.host
          : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
      if (mediaId.isEmpty) return const SizedBox.shrink();

      final stagedBytes = processor?.getStagedBytes(mediaId);
      if (stagedBytes != null) return _staged(stagedBytes, alt, size);
      final attachment = _firstWhere(bioMedia, (a) => a.mediaId == mediaId);
      if (attachment != null) return _widget(attachment, alt, size);
      return const SizedBox.shrink();
    }

    return const SizedBox.shrink();
  }

  Widget _widget(MediaAttachment a, String? alt, BioImageSize size) {
    return BioImageWidget(
      mediaId: a.mediaId,
      encryptionKeyB64: a.encryptionKeyB64,
      ciphertextHash: a.contentHash,
      plaintextHash: a.plaintextHash,
      blurhash: a.blurhash,
      width: a.width,
      height: a.height,
      altText: alt,
      memberName: memberName,
      size: size,
      maxContentWidth: contentWidth,
    );
  }

  Widget _staged(Uint8List bytes, String? alt, BioImageSize size) {
    return BioImageWidget(
      mediaId: '',
      encryptionKeyB64: '',
      ciphertextHash: '',
      plaintextHash: '',
      blurhash: '',
      width: 0,
      height: 0,
      altText: alt,
      memberName: memberName,
      size: size,
      overrideBytes: bytes,
      maxContentWidth: contentWidth,
    );
  }

  MediaAttachment? _firstWhere(
    List<MediaAttachment> list,
    bool Function(MediaAttachment) test,
  ) {
    for (final a in list) {
      if (test(a)) return a;
    }
    return null;
  }
}
