import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/services/bio_image_layout.dart';
import 'package:prism_plurality/features/members/services/bio_markdown_segments.dart';
import 'package:prism_plurality/features/members/services/bio_image_processor.dart';
import 'package:prism_plurality/features/members/services/markdown_table_parser.dart';
import 'package:prism_plurality/features/members/widgets/bio_image_element_builder.dart';
import 'package:prism_plurality/features/members/widgets/prism_markdown_table.dart';
import 'package:prism_plurality/shared/markdown/member_mention_syntax.dart';
import 'package:prism_plurality/shared/widgets/list_detail_layout.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';

/// A [MarkdownText] variant that resolves image references to decrypted
/// [BioImageWidget] instances.
///
/// References are resolved against the shared image library by tag
/// (`![alt](nbflag)`), with backward-compat for legacy `prism-media://<id>`
/// UUIDs. An optional `#WxH` / `#50%` sizing fragment is honored. External
/// URLs (`http`/`https`), `data:`, and `javascript:` are suppressed.
class PrismMarkdownText extends ConsumerWidget {
  const PrismMarkdownText({
    super.key,
    required this.data,
    this.enabled = true,
    this.baseStyle,
    this.selectable = false,
    this.memberId,
    this.memberName,
    this.editSessionId,
    this.mentionsInteractive = true,
  });

  /// The text content (plain or Markdown).
  final String data;

  /// Whether to render as Markdown. When false, displays as plain [Text].
  final bool enabled;

  /// Optional base text style applied to the body text.
  final TextStyle? baseStyle;

  /// Whether the rendered text is selectable.
  final bool selectable;

  /// Whether resolved member mentions should respond to taps.
  final bool mentionsInteractive;

  /// The member whose bio is rendered (for legacy prism-media lookups +
  /// semantics labels). The image library itself is shared across members.
  final String? memberId;

  /// Display name of the member, forwarded to [BioImageWidget] for semantics.
  final String? memberName;

  /// When this text is rendered inside an editor preview, the editor's
  /// processor session id (see [bioImageProcessorProvider]). Lets the preview
  /// resolve staged (uncommitted) images. Null in read-only contexts, where
  /// there is nothing staged to resolve.
  final String? editSessionId;

  bool get _shouldResolveImageReferences {
    if (!enabled) return false;
    return data.contains('![') || data.contains('prism-media://');
  }

  bool get _shouldResolveMemberMentions {
    if (!enabled) return false;
    return containsMemberMention(data);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shouldResolveImageReferences = _shouldResolveImageReferences;
    final shouldResolveMemberMentions = _shouldResolveMemberMentions;

    // Shared image library (all images with non-empty tags).
    final library = shouldResolveImageReferences
        ? ref.watch(imageLibraryProvider).value ?? const <MediaAttachment>[]
        : const <MediaAttachment>[];

    // Member-specific bio media for legacy prism-media:// UUID refs.
    List<MediaAttachment> bioMedia = const [];
    if (shouldResolveImageReferences &&
        memberId != null &&
        memberId!.isNotEmpty) {
      bioMedia = ref.watch(bioMediaForMemberProvider(memberId!)).value ?? [];
    }

    // Processor for staged (uncommitted) image bytes — only when previewing
    // inside an editor session. Guarded for test contexts without media infra.
    BioImageProcessor? processor;
    if (shouldResolveImageReferences && editSessionId != null) {
      try {
        processor = ref.watch(bioImageProcessorProvider(editSessionId!));
      } catch (_) {}
    }

    // Key on all image sources so MarkdownBody re-parses when they change —
    // library version covers add/remove/retag/replace; bioMedia + staged
    // cover the legacy + uncommitted paths. (Watched here, at build scope —
    // not inside the LayoutBuilder below, which runs at layout time.)
    final libraryVersion = shouldResolveImageReferences
        ? ref.watch(imageLibraryVersionProvider)
        : 0;
    final stagedCount = processor?.staged.length ?? 0;
    final mentionMembers = shouldResolveMemberMentions
        ? ref.watch(activeMemberListProvider).value ?? const <Member>[]
        : const <Member>[];
    final mentionMemberMap = {
      for (final member in mentionMembers) member.id: member,
    };
    void openMentionedMember(String memberId) {
      final selectDetail = ListDetailPaneControls.maybeOf(
        context,
      )?.selectDetail;
      if (selectDetail != null) {
        selectDetail(memberId);
        return;
      }
      unawaited(context.push(AppRoutePaths.member(memberId)));
    }

    final onTapMember = mentionsInteractive ? openMentionedMember : null;

    // Measure the available width so percent (`#50%`) image sizing has a real
    // basis: inline images render as WidgetSpan children (unbounded width), so
    // the image can't read the container width itself. The (bucketed) width is
    // folded into the key so a genuine resize re-parses, while tiny layout
    // jitter doesn't thrash MarkdownBody's cached parse.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final hasWidth = width.isFinite;
        final imgBuilder = BioImageElementBuilder(
          library: library,
          bioMedia: bioMedia,
          processor: processor,
          memberName: memberName ?? '',
          contentWidth: hasWidth ? width : null,
        );
        final widthBucket = hasWidth ? width.round() : -1;

        // Size em images for the block/inline heuristic against the same basis
        // they render at (font size × text scaler), else a scaled-up `#2em` is
        // misclassified as inline. Bucketed into the key so a text-size change
        // re-runs the rewrite.
        final emBasisPx = MediaQuery.textScalerOf(
          context,
        ).scale(baseStyle?.fontSize ?? 16.0);
        final emBucket = emBasisPx.round();

        // Split into `:::plain` / `:::#hex` fenced segments so individual
        // tables can opt into a border treatment. No fences → one default
        // segment (identical to before). Each segment is its own MarkdownText
        // because flutter_markdown applies one style sheet per document.
        final normalizedData = enabled
            ? normalizePartialBlockquoteTables(data)
            : data;
        final segments = enabled
            ? parseStyledSegments(normalizedData)
            : [MarkdownSegment(content: data)];

        String keyFor(int seg, int block) =>
            'bio-md-$memberId-$libraryVersion-'
            '${bioMedia.length}-$stagedCount-$widthBucket-em$emBucket-seg$seg-blk$block';

        // A text block reuses the existing MarkdownText path (inline images,
        // bold, links, blockify). A table block is rendered by PrismMarkdownTable
        // so each column can size to its content.
        Widget buildBlock(
          MarkdownSegment seg,
          int segIdx,
          MarkdownBlock block,
          int blockIdx,
        ) {
          if (block.isTable) {
            return PrismMarkdownTable(
              key: ValueKey(keyFor(segIdx, blockIdx)),
              table: block.table!,
              imgElementBuilder: imgBuilder,
              baseStyle: baseStyle,
              memberMap: mentionMemberMap,
              onTapMember: onTapMember,
              borderless: seg.borderless,
              borderColor: seg.borderColor,
            );
          }
          return MarkdownText(
            key: ValueKey(keyFor(segIdx, blockIdx)),
            // Promote large/percent images to their own line (block); keep
            // small ones inline. Only when rendering markdown.
            data: enabled
                ? blockifyImageMarkdown(block.text!, emBasisPx: emBasisPx)
                : block.text!,
            enabled: enabled,
            baseStyle: baseStyle,
            selectable: selectable,
            imgElementBuilder: imgBuilder,
            memberMap: mentionMemberMap,
            onTapMember: onTapMember,
            tableBorderless: seg.borderless,
            tableBorderColor: seg.borderColor,
          );
        }

        // When markdown is disabled there are no tables to extract — render the
        // single segment as plain text (matches prior behavior).
        if (!enabled) {
          return MarkdownText(
            key: ValueKey(keyFor(0, 0)),
            data: segments.first.content,
            enabled: false,
            baseStyle: baseStyle,
            selectable: selectable,
            memberMap: mentionMemberMap,
            onTapMember: onTapMember,
          );
        }

        final blocksPerSegment = [
          for (final seg in segments) splitMarkdownBlocks(seg.content),
        ];

        // Fast path: one default segment that is a single text block (the
        // common no-table case) → one bare MarkdownText, no wrapping Column.
        if (segments.length == 1 &&
            segments.first.isDefault &&
            blocksPerSegment.first.length == 1 &&
            !blocksPerSegment.first.first.isTable) {
          return buildBlock(segments.first, 0, blocksPerSegment.first.first, 0);
        }

        final children = <Widget>[];
        for (var s = 0; s < segments.length; s++) {
          if (s > 0) children.add(const SizedBox(height: 8));
          final blocks = blocksPerSegment[s];
          for (var b = 0; b < blocks.length; b++) {
            if (b > 0) children.add(const SizedBox(height: 8));
            children.add(buildBlock(segments[s], s, blocks[b], b));
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        );
      },
    );
  }
}
