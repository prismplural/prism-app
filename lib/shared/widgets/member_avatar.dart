import 'dart:typed_data';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Reusable circular avatar widget for system members.
///
/// Displays the member's avatar image if available, otherwise falls back
/// to their emoji in a colored circle. The circle color uses the member's
/// custom color when enabled, or the theme primary color.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    this.avatarImageData,
    this.memberName,
    this.emoji = '❔',
    this.customColorEnabled = false,
    this.customColorHex,
    this.size = 40,
    this.showBorder = false,
    this.tintOverride,
    this.opacity = 1.0,
  });

  final Uint8List? avatarImageData;

  /// Optional member name used as the semantic label for the avatar image.
  final String? memberName;

  final String emoji;
  final bool customColorEnabled;
  final String? customColorHex;
  final double size;
  final bool showBorder;

  /// When set, overrides the derived member/theme color for the glass tint.
  final Color? tintOverride;

  /// Visual opacity (0.0–1.0). Applied at the paint level without a
  /// compositing layer, so it is safe to use in scrolling surfaces.
  final double opacity;

  Color _circleColor(BuildContext context) {
    if (tintOverride != null) return tintOverride!;
    if (customColorEnabled && customColorHex != null) {
      return AppColors.fromHex(customColorHex!);
    }
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final color = _circleColor(context);
    final dimmed = opacity < 1.0;
    final tint = dimmed ? color.withValues(alpha: color.a * opacity) : color;

    Widget child;
    if (avatarImageData != null && avatarImageData!.isNotEmpty) {
      final imageInset = size * 0.1;
      final imageSize = size - imageInset * 2;
      final pixelSize = (imageSize * MediaQuery.devicePixelRatioOf(context)).ceil();
      child = TintedGlassSurface.circle(
        size: size,
        tint: tint,
        child: ClipOval(
          child: Image.memory(
            avatarImageData!,
            width: imageSize,
            height: imageSize,
            cacheWidth: pixelSize,
            cacheHeight: pixelSize,
            fit: BoxFit.cover,
            semanticLabel: memberName != null
                ? context.l10n.memberAvatarSemantics(memberName!)
                : context.l10n.memberAvatarSemanticsUnnamed,
            color: dimmed ? Color.fromRGBO(255, 255, 255, opacity) : null,
            colorBlendMode: dimmed ? BlendMode.modulate : null,
            errorBuilder: (_, _, _) => _centeredEmoji(size),
          ),
        ),
      );
    } else {
      child = _emojiCircle(tint);
      // Emoji glyphs are platform-rendered and cannot be tinted via paint-level
      // alpha, so we fall back to Opacity for the small circle widget.
      if (dimmed) {
        child = Opacity(opacity: opacity, child: child);
      }
    }

    if (showBorder) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: child,
        ),
      );
    }

    return child;
  }

  Widget _emojiCircle(Color color) {
    return TintedGlassSurface.circle(
      size: size,
      tint: color,
      child: _centeredEmoji(size),
    );
  }

  /// Renders an emoji with platform-aware centering.
  ///
  /// Apple Color Emoji glyphs are scaled differently by CoreText vs Skia,
  /// causing off-center rendering on iOS/macOS. This compensates with a
  /// small downward + leftward nudge and padding, plus text metrics fixes.
  static Widget centeredEmoji(String emoji, {required double fontSize}) {
    final isApple = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    Widget text = Text(
      emoji,
      strutStyle: StrutStyle.disabled,
      style: TextStyle(
        fontSize: fontSize,
        height: 1.0,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );

    // At small sizes on Apple, CoreText's advance width is wider than the
    // visual glyph, pushing it left of center. The mismatch fades by ~23pt.
    if (isApple && fontSize < 22) {
      text = Transform.translate(
        offset: Offset(fontSize * 0.06, 0),
        child: text,
      );
    }

    return text;
  }

  Widget _centeredEmoji(double containerSize) {
    return MemberAvatar.centeredEmoji(emoji, fontSize: containerSize * 0.5);
  }
}
