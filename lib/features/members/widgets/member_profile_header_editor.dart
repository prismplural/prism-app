import 'package:flutter/foundation.dart';
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
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class MemberProfileHeaderEditor extends StatelessWidget {
  const MemberProfileHeaderEditor({
    super.key,
    required this.member,
    required this.source,
    required this.layout,
    required this.visible,
    required this.prismHeaderImageData,
    required this.onSourceChanged,
    required this.onLayoutChanged,
    required this.onVisibleChanged,
    required this.onPrismHeaderImageChanged,
    this.pluralKitHeaderImageData,
    this.pluralKitEligible,
    this.onPrismHeaderImageRemoved,
    this.onAvatarTap,
    this.onAvatarRemove,
    this.onNameStyleTap,
    this.showSectionWrapper = true,
    @visibleForTesting this.pickCroppedHeaderBytes,
  });

  final Member member;
  final MemberProfileHeaderSource source;
  final MemberProfileHeaderLayout layout;
  final bool visible;
  final Uint8List? prismHeaderImageData;
  final Uint8List? pluralKitHeaderImageData;
  final bool? pluralKitEligible;
  final ValueChanged<MemberProfileHeaderSource> onSourceChanged;
  final ValueChanged<MemberProfileHeaderLayout> onLayoutChanged;
  final ValueChanged<bool> onVisibleChanged;
  final ValueChanged<Uint8List?> onPrismHeaderImageChanged;
  final VoidCallback? onPrismHeaderImageRemoved;

  /// Tapping the avatar inside the preview triggers this — typically opens
  /// the system avatar picker.
  final VoidCallback? onAvatarTap;

  /// When set and the member has an avatar image, a small remove control is
  /// rendered in the corner of the preview avatar.
  final VoidCallback? onAvatarRemove;

  /// Opens the member name style controls from the preview header.
  final VoidCallback? onNameStyleTap;

  /// When false, renders without the [PrismSection] title/description wrapper.
  /// Use in dedicated-tab contexts where the tab itself provides the framing.
  final bool showSectionWrapper;

  @visibleForTesting
  final Future<Uint8List?> Function(BuildContext context)?
  pickCroppedHeaderBytes;

  Future<void> _changePrismHeader(BuildContext context) async {
    if (source == MemberProfileHeaderSource.pluralKit) {
      onSourceChanged(MemberProfileHeaderSource.prism);
    }
    try {
      final bytes =
          await (pickCroppedHeaderBytes ??
              ProfileHeaderImagePicker.pickCroppedHeaderBytes)(context);
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

    final theme = Theme.of(context);
    final canRemovePrismImage =
        previewSource == MemberProfileHeaderSource.prism &&
        prismHeaderImageData != null &&
        prismHeaderImageData!.isNotEmpty;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          PrismSectionCard(
            padding: const EdgeInsets.all(12),
            child: MemberProfileHeader(
              member: member,
              source: previewSource,
              layout: layout,
              visible: visible,
              prismHeaderImageData: prismHeaderImageData,
              pluralKitHeaderImageData: pluralKitHeaderImageData,
              onAvatarTap: onAvatarTap,
              onAvatarRemove: onAvatarRemove,
              onNameStyleTap: onNameStyleTap,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              PrismButton(
                icon: AppIcons.imageOutlined,
                label: prismHeaderImageData != null &&
                        prismHeaderImageData!.isNotEmpty
                    ? context.l10n.memberProfileHeaderChangeImage
                    : context.l10n.memberProfileHeaderAddImage,
                onPressed: () => _changePrismHeader(context),
                density: PrismControlDensity.compact,
              ),
              if (canRemovePrismImage) ...[
                const SizedBox(width: 8),
                PrismButton(
                  icon: AppIcons.deleteOutline,
                  label: context.l10n.memberProfileHeaderRemoveImage,
                  tone: PrismButtonTone.destructive,
                  density: PrismControlDensity.compact,
                  onPressed: () {
                    onPrismHeaderImageChanged(null);
                    onPrismHeaderImageRemoved?.call();
                  },
                ),
              ],
            ],
          ),
          if (resolvedPluralKitEligible) ...[
            const SizedBox(height: 16),
            PrismSegmentedControl<MemberProfileHeaderSource>(
              selected: previewSource,
              onChanged: onSourceChanged,
              segments: [
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
            const SizedBox(height: 6),
            Text(
              previewSource == MemberProfileHeaderSource.pluralKit
                  ? context.l10n.memberProfileHeaderSourcePluralKitHelper
                  : context.l10n.memberProfileHeaderSourcePrismHelper,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            context.l10n.memberProfileHeaderLayoutLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
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
          const SizedBox(height: 12),
          PrismSwitchRow(
            title: context.l10n.memberProfileHeaderHideTitle,
            subtitle: context.l10n.memberProfileHeaderVisibleSubtitle,
            value: !visible,
            onChanged: (v) => onVisibleChanged(!v),
            icon: AppIcons.imageOutlined,
          ),
        ],
      );
    if (!showSectionWrapper) return content;
    return PrismSection(
      title: context.l10n.memberProfileHeaderSectionTitle,
      description: context.l10n.memberProfileHeaderSectionDescription,
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: content,
    );
  }
}
