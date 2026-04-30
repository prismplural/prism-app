import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/utils/member_profile_header_resolver.dart';
import 'package:prism_plurality/features/members/widgets/member_profile_header.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/profile_header_image_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class MemberProfileHeaderEditor extends StatelessWidget {
  const MemberProfileHeaderEditor({
    super.key,
    required this.member,
    required this.source,
    required this.layout,
    required this.prismHeaderImageData,
    required this.onSourceChanged,
    required this.onLayoutChanged,
    required this.onPrismHeaderImageChanged,
    this.pluralKitHeaderImageData,
    this.pluralKitEligible,
    this.onPrismHeaderImageRemoved,
  });

  final Member member;
  final MemberProfileHeaderSource source;
  final MemberProfileHeaderLayout layout;
  final Uint8List? prismHeaderImageData;
  final Uint8List? pluralKitHeaderImageData;
  final bool? pluralKitEligible;
  final ValueChanged<MemberProfileHeaderSource> onSourceChanged;
  final ValueChanged<MemberProfileHeaderLayout> onLayoutChanged;
  final ValueChanged<Uint8List?> onPrismHeaderImageChanged;
  final VoidCallback? onPrismHeaderImageRemoved;

  Future<void> _changePrismHeader(BuildContext context) async {
    if (source == MemberProfileHeaderSource.pluralKit) {
      onSourceChanged(MemberProfileHeaderSource.prism);
    }
    try {
      final bytes = await ProfileHeaderImagePicker.pickCroppedHeaderBytes(
        context,
      );
      if (bytes != null) {
        onPrismHeaderImageChanged(bytes);
      }
    } catch (_) {
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.memberProfileHeaderProcessingError,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedPluralKitEligible =
        pluralKitEligible ??
        memberHasEligiblePluralKitHeader(
          member,
          pluralKitImageDataOverride: pluralKitHeaderImageData,
        );
    final previewSource =
        source == MemberProfileHeaderSource.pluralKit &&
            !resolvedPluralKitEligible
        ? MemberProfileHeaderSource.prism
        : source;

    return PrismSection(
      title: context.l10n.memberProfileHeaderSectionTitle,
      description: context.l10n.memberProfileHeaderSectionDescription,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrismSegmentedControl<MemberProfileHeaderSource>(
            selected: previewSource,
            onChanged: onSourceChanged,
            segments: [
              if (resolvedPluralKitEligible)
                PrismSegment(
                  value: MemberProfileHeaderSource.pluralKit,
                  label: context.l10n.memberProfileHeaderSourcePluralKit,
                ),
              PrismSegment(
                value: MemberProfileHeaderSource.prism,
                label: context.l10n.memberProfileHeaderSourcePrism,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            previewSource == MemberProfileHeaderSource.pluralKit
                ? context.l10n.memberProfileHeaderSourcePluralKitHelper
                : context.l10n.memberProfileHeaderSourcePrismHelper,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (!resolvedPluralKitEligible) ...[
            const SizedBox(height: 4),
            Text(
              context.l10n.memberProfileHeaderPluralKitUnavailable,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          PrismSectionCard(
            padding: const EdgeInsets.all(12),
            child: MemberProfileHeader(
              member: member,
              source: previewSource,
              layout: layout,
              prismHeaderImageData: prismHeaderImageData,
              pluralKitHeaderImageData: pluralKitHeaderImageData,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PrismButton(
                label: context.l10n.memberProfileHeaderChangeImage,
                icon: AppIcons.imageOutlined,
                density: PrismControlDensity.compact,
                onPressed: () => _changePrismHeader(context),
              ),
              PrismButton(
                label: context.l10n.memberProfileHeaderRemoveImage,
                icon: AppIcons.deleteOutline,
                density: PrismControlDensity.compact,
                tone: PrismButtonTone.destructive,
                enabled:
                    previewSource == MemberProfileHeaderSource.prism &&
                    prismHeaderImageData != null &&
                    prismHeaderImageData!.isNotEmpty,
                onPressed: () {
                  onPrismHeaderImageChanged(null);
                  onPrismHeaderImageRemoved?.call();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.memberProfileHeaderLayoutLabel,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.56),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          PrismSegmentedControl<MemberProfileHeaderLayout>(
            selected: layout,
            onChanged: onLayoutChanged,
            segments: [
              PrismSegment(
                value: MemberProfileHeaderLayout.compactBackground,
                label: context.l10n.memberProfileHeaderLayoutCompact,
              ),
              PrismSegment(
                value: MemberProfileHeaderLayout.classicOverlap,
                label: context.l10n.memberProfileHeaderLayoutClassic,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
