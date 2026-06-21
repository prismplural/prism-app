import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/core/sharing/field_template_codec.dart';
import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/widgets/branded_template_card.dart';
import 'package:prism_plurality/features/settings/widgets/field_template_summary.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// "Share as template" sheet: a branded card with a scannable QR, a Copy
/// primary action, an image save/share action, and a "what's included" list.
class ShareTemplateSheet {
  static Future<void> show(
    BuildContext context, {
    required FieldTemplate template,
  }) {
    return PrismSheet.showFullScreen(
      context: context,
      builder: (ctx, scrollController) => ShareTemplateSheetContent(
        template: template,
        scrollController: scrollController,
      ),
    );
  }
}

class ShareTemplateSheetContent extends ConsumerStatefulWidget {
  const ShareTemplateSheetContent({
    super.key,
    required this.template,
    this.scrollController,
  });

  final FieldTemplate template;
  final ScrollController? scrollController;

  @override
  ConsumerState<ShareTemplateSheetContent> createState() =>
      _ShareTemplateSheetContentState();
}

class _ShareTemplateSheetContentState
    extends ConsumerState<ShareTemplateSheetContent> {
  final _cardKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  late final String _code = const FieldTemplateCodec().encode(widget.template);
  // Inflate once: toDomainFields mints fresh ids, so re-mapping these on each
  // rebuild stays cheap and id-stable.
  late final _domainFields = widget.template.toDomainFields();
  bool _busy = false;

  bool get _isDesktop => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _code));
    if (mounted) {
      PrismToast.show(
        context,
        message: context.l10n.fieldTemplateShareCopiedToast,
      );
    }
  }

  Future<void> _saveOrShareImage() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = context.l10n;
    try {
      final png = await captureBrandedTemplateCardPng(_cardKey, code: _code);
      if (png == null) {
        if (mounted) {
          PrismToast.error(context, message: l10n.fieldTemplateShareImageFailed);
        }
        return;
      }
      // The sheet may have been dismissed during capture — guard the ref/context
      // use that follows in both branches.
      if (!mounted) return;

      if (_isDesktop) {
        final outcome = await ref
            .read(prismFileDialogServiceProvider)
            .saveBytes(
              bytes: png,
              suggestedName: _imageFileName(),
              allowedExtensions: const ['png'],
              mimeType: 'image/png',
              dialogTitle: l10n.fieldTemplateShareSaveImage,
            );
        if (!mounted) return;
        if (outcome.didSave) {
          PrismToast.show(context, message: l10n.fieldTemplateShareImageSaved);
        } else if (outcome.status != SaveFileStatus.cancelled &&
            outcome.status != SaveFileStatus.alreadyActive) {
          PrismToast.error(context, message: l10n.fieldTemplateShareImageFailed);
        }
      } else {
        final origin = _shareOrigin();
        final dir = await getTemporaryDirectory();
        final file = File(p.join(dir.path, _imageFileName()));
        await file.writeAsBytes(png, flush: true);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            subject: l10n.fieldTemplateShareSubject,
            sharePositionOrigin: origin,
          ),
        );
        // Share has consumed the bytes by now; don't leave temp files behind.
        try {
          await file.delete();
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        PrismToast.error(context, message: l10n.fieldTemplateShareImageFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _imageFileName() {
    final raw = widget.template.entries.isNotEmpty
        ? widget.template.entries.first.name.trim()
        : '';
    final base = (raw.isEmpty ? 'Prism' : raw).replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    );
    return '$base field template.png';
  }

  Rect? _shareOrigin() {
    final box = _shareButtonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final terms = watchTerminology(context, ref);
    final summary = summarizeDomainFields(
      l10n,
      _domainFields,
      memberTypeLabel: terms.singular,
      groupNameFallback: l10n.customFieldGroupUntitledFallback,
    );
    final name = summary.isNotEmpty ? summary.first.name : '';
    final fieldCount = summary.where((item) => !item.isGroup).length;
    final typeLabels = <String>[];
    final seen = <String>{};
    for (final item in summary) {
      if (!item.isGroup && seen.add(item.typeLabel)) {
        typeLabels.add(item.typeLabel);
      }
    }
    final hasQr = qrEccForCodeLength(_code.length) != null;

    return Column(
      children: [
        PrismSheetTopBar(title: l10n.fieldTemplateShareTitle),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The card has a fixed intrinsic width so the captured PNG is
                // consistent; scale the on-screen preview down to fit narrower
                // phones. The RepaintBoundary capture is unaffected by this.
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BrandedTemplateCard(
                      boundaryKey: _cardKey,
                      name: name,
                      code: _code,
                      fieldCount: fieldCount,
                      typeLabels: typeLabels,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: PrismButton(
                        label: l10n.fieldTemplateShareCopy,
                        icon: AppIcons.copy,
                        tone: PrismButtonTone.filled,
                        onPressed: _copyCode,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrismButton(
                        key: _shareButtonKey,
                        label: _isDesktop
                            ? l10n.fieldTemplateShareSaveImage
                            : l10n.fieldTemplateShareShareImage,
                        icon: _isDesktop ? AppIcons.download : AppIcons.share,
                        tone: PrismButtonTone.subtle,
                        isLoading: _busy,
                        onPressed: _saveOrShareImage,
                      ),
                    ),
                  ],
                ),
                if (!hasQr) ...[
                  const SizedBox(height: 12),
                  _InlineNote(text: l10n.fieldTemplateShareNoQrWarning),
                ],
                if (_isDesktop) ...[
                  const SizedBox(height: 20),
                  _SelectableCode(label: l10n.fieldTemplateShareTextLabel, code: _code),
                ],
                const SizedBox(height: 24),
                Text(
                  l10n.fieldTemplateShareWhatsIncluded,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                for (final item in summary)
                  FieldTemplateSummaryRow(item: item),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismSurface(
      tone: PrismSurfaceTone.subtle,
      accentColor: AppColors.warning,
      borderRadius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.infoOutline, color: AppColors.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableCode extends StatelessWidget {
  const _SelectableCode({required this.label, required this.code});

  final String label;
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(PrismTokens.radiusSmall),
            ),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: SelectableText(
            code,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
