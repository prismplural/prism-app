import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:prism_plurality/core/sharing/field_template_png.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

/// Logical width of the rendered card. Fixed so the captured PNG is consistent
/// regardless of the surrounding layout.
const double _kCardWidth = 380;

const String _kLogoAsset = 'assets/icon_layers/Prism-Logo-Foreground.png';

/// Brand spectrum, ordered like real prism dispersion (warm → cool → violet).
/// Uses the app's actual accent palette, never the user's seeded accent.
const List<Color> _kSpectrum = [
  AppColors.accentRoseDark,
  AppColors.accentAmberDark,
  AppColors.accentSageDark,
  AppColors.accentBlueDark,
  AppColors.accentPurpleDark,
  AppColors.accentLavenderDark,
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

/// A fixed-palette, shareable card for a field template: prism mark, spectrum
/// rule, wordmark, the template name + type chips, a scannable QR beside the
/// mark, and the code printed beneath. Wrap with [boundaryKey] to capture it.
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
    const onCard = AppColors.warmBlack;
    final muted = AppColors.warmBlack.withValues(alpha: 0.6);

    return RepaintBoundary(
      key: boundaryKey,
      child: Container(
        width: _kCardWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.warmOffWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.warmBlack.withValues(alpha: 0.08)),
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
                      const Text(
                        'Prism',
                        style: TextStyle(
                          fontFamily: 'Unbounded',
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          letterSpacing: 0.5,
                          color: onCard,
                        ),
                      ),
                      const Spacer(),
                      _Kicker(label: l10n.fieldTemplateCardKicker),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: onCard,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.fieldTemplateFieldCount(fieldCount),
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                  if (typeLabels.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final label in typeLabels) _TypeChip(label: label),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const _MarkChip(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'prismplural.com',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.prismPurpleLight,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.fieldTemplateCardScanHint,
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ],
                        ),
                      ),
                      if (ecc != null) ...[
                        const SizedBox(width: 12),
                        _QrBox(code: code, ecc: ecc, name: name),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    code,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      height: 1.3,
                      color: muted,
                    ),
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
  const _Kicker({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.prismPurple.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.prismPurpleLight,
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.prismPurple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.warmBlack,
        ),
      ),
    );
  }
}

class _MarkChip extends StatelessWidget {
  const _MarkChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.prismPurple,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Image.asset(_kLogoAsset, width: 24, height: 24),
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
          size: 122,
          backgroundColor: Colors.white,
          // The card carries the mark beside the QR; an overlay would force
          // ECC-H and cost capacity, so the code stays unobstructed.
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: AppColors.warmBlack,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: AppColors.warmBlack,
          ),
        ),
      ),
    );
  }
}
