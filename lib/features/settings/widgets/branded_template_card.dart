import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:prism_plurality/core/sharing/field_template_png.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Logical width of the rendered card. Fixed so the captured PNG is consistent
/// regardless of the surrounding layout.
const double _kCardWidth = 640;
const double _kQrImageSize = 340;

const String _kLogoAsset = 'assets/icon_layers/Prism-Logo-Foreground.png';

const Color _kBrandPurple = Color(0xFFB498C2);
const Color _kBrandPurpleLight = Color(0xFF9070A0);

/// Brand spectrum, ordered like real prism dispersion (warm -> cool -> violet).
/// Uses Prism's fixed accent palette, never the user's seeded accent.
const List<Color> _kSpectrum = [
  Color(0xFFC98E8E),
  Color(0xFFB58D67),
  Color(0xFF8DA399),
  Color(0xFF7A9BA8),
  _kBrandPurple,
  Color(0xFF9B8EAD),
];

/// QR error-correction level for a code of [length] chars, or null when the
/// code is too long to fit a single scannable QR (callers omit the QR and fall
/// back to the printed code / file). Ceilings are the QR v40 byte-mode caps.
///
/// Assumes ASCII: the codec emits `PF1:` + base64url, so char count == UTF-8
/// byte count. A future non-ASCII code would need a byte-length measure here.
int? qrEccForCodeLength(int length) {
  if (length <= 1273) return QrErrorCorrectLevel.H;
  if (length <= 1663) return QrErrorCorrectLevel.Q;
  if (length <= 2331) return QrErrorCorrectLevel.M;
  if (length <= 2953) return QrErrorCorrectLevel.L;
  return null;
}

/// Captures the card behind [boundaryKey] to PNG bytes with the share [code]
/// embedded in a tEXt chunk. Returns null if the boundary isn't mounted yet.
Future<Uint8List?> captureBrandedTemplateCardPng(
  GlobalKey boundaryKey, {
  required String code,
  double pixelRatio = 3,
}) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    return embedTemplateInPng(bytes.buffer.asUint8List(), code);
  } finally {
    image.dispose();
  }
}

/// A shareable card for a field template: prism mark, spectrum rule, wordmark,
/// the template name + type chips, and a scannable QR beside the mark. Follows
/// the app's light/dark brightness (the QR box stays white to scan); the full
/// code is carried by the QR + the embedded tEXt chunk, never printed. Wrap with
/// [boundaryKey] to capture it.
class BrandedTemplateCard extends StatelessWidget {
  const BrandedTemplateCard({
    super.key,
    required this.name,
    required this.code,
    required this.fieldCount,
    required this.typeLabels,
    this.boundaryKey,
  });

  final String name;
  final String code;
  final int fieldCount;

  /// De-duplicated, already-localized field-type labels shown as chips.
  final List<String> typeLabels;

  /// Optional [RepaintBoundary] key used by [captureBrandedTemplateCardPng].
  final GlobalKey? boundaryKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ecc = qrEccForCodeLength(code.length);
    final c = _CardPalette.of(context);

    return RepaintBoundary(
      key: boundaryKey,
      child: Container(
        width: _kCardWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (final color in _kSpectrum)
                  Expanded(child: Container(height: 6, color: color)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Prism',
                        style: TextStyle(
                          fontFamily: 'Unbounded',
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          letterSpacing: 0.5,
                          color: c.onCard,
                        ),
                      ),
                      const Spacer(),
                      _Kicker(label: l10n.fieldTemplateCardKicker, palette: c),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: c.onCard,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.fieldTemplateFieldCount(fieldCount),
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                  if (typeLabels.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final label in typeLabels)
                          _TypeChip(label: label, palette: c),
                      ],
                    ),
                  ],
                  const SizedBox(height: 28),
                  // QR/metadata carry the code; oversized payloads fall back.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ecc != null
                        ? _QrBox(code: code, ecc: ecc, name: name)
                        : _NoQrNote(palette: c),
                  ),
                  const SizedBox(height: 18),
                  _FooterLine(
                    palette: c,
                    hint: ecc != null
                        ? l10n.fieldTemplateCardScanHint
                        : l10n.fieldTemplateCardCopyHint,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Kicker extends StatelessWidget {
  const _Kicker({required this.label, required this.palette});

  final String label;
  final _CardPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.kickerBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: palette.brand,
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.palette});

  final String label;
  final _CardPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.chipBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: palette.chipText,
        ),
      ),
    );
  }
}

class _MarkChip extends StatelessWidget {
  const _MarkChip({
    required this.color,
    this.size = 40,
    this.imageSize = 24,
    this.borderRadius = 11,
  });

  final Color color;
  final double size;
  final double imageSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: Image.asset(_kLogoAsset, width: imageSize, height: imageSize),
    );
  }
}

class _FooterLine extends StatelessWidget {
  const _FooterLine({required this.palette, required this.hint});

  final _CardPalette palette;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MarkChip(
          color: palette.brand,
          size: 26,
          imageSize: 16,
          borderRadius: 7,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(
                fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                fontSize: 14,
                height: 1.2,
                color: palette.muted,
              ),
              children: [
                TextSpan(
                  text: 'prismplural.com',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: palette.brand,
                  ),
                ),
                TextSpan(text: '  $hint'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QrBox extends StatelessWidget {
  const _QrBox({required this.code, required this.ecc, required this.name});

  final String code;
  final int ecc;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: context.l10n.fieldTemplateQrSemanticLabel(name),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: QrImageView(
          data: code,
          version: QrVersions.auto,
          errorCorrectionLevel: ecc,
          size: _kQrImageSize,
          padding: const EdgeInsets.all(16),
          backgroundColor: Colors.white,
          // The card carries the mark beside the QR; an overlay would force
          // ECC-H and cost capacity, so the code stays unobstructed.
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

/// Card palette resolved from the app brightness. Brand accents stay constant;
/// surface/text/chip tones flip for dark mode. The QR box is white regardless
/// (see [_QrBox]) so it always scans.
class _CardPalette {
  const _CardPalette({
    required this.bg,
    required this.onCard,
    required this.muted,
    required this.border,
    required this.brand,
    required this.chipBg,
    required this.chipText,
    required this.kickerBg,
  });

  factory _CardPalette.of(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final onCard = colorScheme.onSurface;
    final brand = dark ? _kBrandPurple : _kBrandPurpleLight;
    return _CardPalette(
      bg: dark
          ? colorScheme.surfaceContainerHighest
          : colorScheme.surfaceContainerLowest,
      onCard: onCard,
      muted: colorScheme.onSurfaceVariant,
      border: colorScheme.outlineVariant.withValues(alpha: dark ? 0.42 : 0.62),
      brand: brand,
      chipBg: brand.withValues(alpha: dark ? 0.22 : 0.12),
      chipText: onCard,
      kickerBg: brand.withValues(alpha: dark ? 0.24 : 0.16),
    );
  }

  final Color bg;
  final Color onCard;
  final Color muted;
  final Color border;
  final Color brand;
  final Color chipBg;
  final Color chipText;
  final Color kickerBg;
}

/// Shown in the QR's place when the code is too long to fit a scannable QR.
class _NoQrNote extends StatelessWidget {
  const _NoQrNote({required this.palette});

  final _CardPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 146,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: palette.chipBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.infoOutline, size: 22, color: palette.brand),
          const SizedBox(height: 8),
          Text(
            context.l10n.fieldTemplateCardNoQr,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: palette.onCard.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
