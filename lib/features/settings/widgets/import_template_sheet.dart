import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/core/sharing/field_template_codec.dart';
import 'package:prism_plurality/core/sharing/field_template_png.dart';
import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/features/settings/services/field_template_import_service.dart';
import 'package:prism_plurality/features/settings/widgets/template_preview_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Entry point for importing a shared field template: paste the template,
/// choose a saved image, or (on mobile) scan its QR. A good decode opens the
/// preview sheet; confirming there imports the fields.
class ImportTemplateSheet {
  static Future<void> show(BuildContext context) {
    return PrismSheet.showFullScreen(
      context: context,
      builder: (ctx, scrollController) =>
          ImportTemplateSheetContent(scrollController: scrollController),
    );
  }
}

enum _ImportStep { input, scanning, importing }

class ImportTemplateSheetContent extends ConsumerStatefulWidget {
  const ImportTemplateSheetContent({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<ImportTemplateSheetContent> createState() =>
      _ImportTemplateSheetContentState();
}

class _ImportTemplateSheetContentState
    extends ConsumerState<ImportTemplateSheetContent> {
  final _pasteController = TextEditingController();
  _ImportStep _step = _ImportStep.input;
  String? _error;
  MobileScannerController? _scanController;
  bool _handlingScan = false;
  bool _busy = false;

  // A template image is tiny; reject anything implausibly large before we read
  // and PNG-decode the picked file.
  static const _maxImageBytes = 16 * 1024 * 1024;

  bool get _scanSupported => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

  @override
  void dispose() {
    _pasteController.dispose();
    _scanController?.dispose();
    super.dispose();
  }

  void _enterScan() {
    setState(() {
      _error = null;
      _handlingScan = false;
      _step = _ImportStep.scanning;
      _scanController = MobileScannerController();
    });
  }

  void _leaveScan() {
    _scanController?.dispose();
    _scanController = null;
    if (mounted) setState(() => _step = _ImportStep.input);
  }

  String _friendlyError(FieldTemplateCodecException e, String raw) {
    final l10n = context.l10n;
    // The codec rejects any non-PF1 prefix as "unsupported version", but a typo
    // or wrong paste should read as "doesn't look right" — only a genuine
    // PF<n>: with n != 1 is actually a newer version.
    if (e.kind == FieldTemplateCodecError.unsupportedVersion &&
        _looksLikeNewerVersion(raw)) {
      return l10n.fieldTemplateImportErrorVersion;
    }
    return l10n.fieldTemplateImportErrorInvalid;
  }

  bool _looksLikeNewerVersion(String raw) {
    final match = RegExp(r'^PF(\d+):').firstMatch(raw.trim());
    if (match == null) return false;
    return int.tryParse(match.group(1)!) != 1;
  }

  /// Runs [action] unless another candidate is already in flight; guards
  /// double-taps that would otherwise stack preview sheets or file pickers.
  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Decode a candidate string and, on success, open the preview → import flow.
  Future<void> _processCandidate(String raw) async {
    final FieldTemplate template;
    try {
      template = const FieldTemplateCodec().decode(raw.trim());
      // Materialize now: a hostile code can pass structural validation but carry
      // a malformed compactConfig that throws when inflated. Surfacing it here
      // keeps the preview (which re-materializes) from crashing mid-build.
      template.toDomainFields();
    } on FieldTemplateCodecException catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e, raw));
      return;
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.fieldTemplateImportErrorInvalid);
      }
      return;
    }
    if (!mounted) return;
    final confirmed = await TemplatePreviewSheet.show(
      context,
      template: template,
    );
    if (confirmed != true || !mounted) return;
    await _import(template);
  }

  Future<void> _import(FieldTemplate template) async {
    setState(() {
      _step = _ImportStep.importing;
      _error = null;
    });
    try {
      await ref
          .read(fieldTemplateImportServiceProvider)
          .importTemplate(template);
      if (!mounted) return;
      final name = _rootName(template);
      // Count the fields inside, not the group container, to match "N fields".
      final count = template.entries
          .where((e) => e.fieldTypeId != 'group')
          .length;
      // Show the toast before popping so it lands on the screen behind us.
      PrismToast.show(
        context,
        message: context.l10n.fieldTemplateImportSuccessToast(name, count),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _step = _ImportStep.input;
        _error = context.l10n.fieldTemplateImportErrorFailed;
      });
    }
  }

  String _rootName(FieldTemplate template) {
    if (template.entries.isEmpty) return '';
    final first = template.entries.first;
    if (first.fieldTypeId == 'group' && first.name.trim().isEmpty) {
      return context.l10n.customFieldGroupUntitledFallback;
    }
    return first.name;
  }

  Future<void> _pickImage() async {
    final l10n = context.l10n;
    final handle = await ref
        .read(prismFileDialogServiceProvider)
        .pickFile(allowedExtensions: const ['png']);
    if (handle == null || !mounted) return;
    if ((handle.size ?? 0) > _maxImageBytes) {
      setState(() => _error = l10n.fieldTemplateImportErrorNoImage);
      return;
    }

    String? code;
    try {
      final bytes = await handle.readAsBytes();
      code = readTemplateFromPng(bytes);
      // No tEXt chunk (e.g. a re-compressed screenshot): fall back to decoding
      // the visible QR from the image file (path-based) where supported.
      if (code == null && _scanSupported && handle.path != null) {
        code = await _decodeQrFromImage(handle.path!);
      }
    } catch (_) {
      // A corrupt or oversized file can throw in readAsBytes or PNG decode.
      if (mounted) setState(() => _error = l10n.fieldTemplateImportErrorNoImage);
      return;
    }
    if (!mounted) return;
    if (code == null) {
      setState(() => _error = l10n.fieldTemplateImportErrorNoImage);
      return;
    }
    await _processCandidate(code);
  }

  Future<String?> _decodeQrFromImage(String path) async {
    final controller = MobileScannerController();
    try {
      final capture = await controller.analyzeImage(path);
      return capture?.barcodes.firstOrNull?.rawValue;
    } catch (_) {
      return null;
    } finally {
      await controller.dispose();
    }
  }

  void _onScanDetect(BarcodeCapture capture) {
    if (_handlingScan) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    _handlingScan = true;
    _leaveScan();
    _guard(() => _processCandidate(raw));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      children: [
        PrismSheetTopBar(title: l10n.fieldTemplateImportTitle),
        Expanded(
          child: switch (_step) {
            _ImportStep.importing => Center(
              child: PrismSpinner(color: theme.colorScheme.primary),
            ),
            _ImportStep.scanning => _ScanView(
              controller: _scanController!,
              onDetect: _onScanDetect,
              onBack: _leaveScan,
            ),
            _ImportStep.input => _InputView(
              scrollController: widget.scrollController,
              pasteController: _pasteController,
              error: _error,
              scanSupported: _scanSupported,
              busy: _busy,
              onImportPasted: () =>
                  _guard(() => _processCandidate(_pasteController.text)),
              onChooseImage: () => _guard(_pickImage),
              onScan: _enterScan,
            ),
          },
        ),
      ],
    );
  }
}

class _InputView extends StatelessWidget {
  const _InputView({
    required this.scrollController,
    required this.pasteController,
    required this.error,
    required this.scanSupported,
    required this.busy,
    required this.onImportPasted,
    required this.onChooseImage,
    required this.onScan,
  });

  final ScrollController? scrollController;
  final TextEditingController pasteController;
  final String? error;
  final bool scanSupported;
  final bool busy;
  final VoidCallback onImportPasted;
  final VoidCallback onChooseImage;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.fieldTemplateImportDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          PrismTextField(
            controller: pasteController,
            labelText: l10n.fieldTemplateImportPasteLabel,
            hintText: 'PF1:…',
            minLines: 3,
            maxLines: 5,
            errorText: error,
            textCapitalization: TextCapitalization.none,
          ),
          const SizedBox(height: 12),
          PrismButton(
            label: l10n.fieldTemplateImportPasteAction,
            icon: AppIcons.check,
            tone: PrismButtonTone.filled,
            enabled: !busy,
            onPressed: onImportPasted,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  l10n.fieldTemplateImportDividerOr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          PrismButton(
            label: l10n.fieldTemplateImportChooseImage,
            icon: AppIcons.imageOutlined,
            tone: PrismButtonTone.subtle,
            enabled: !busy,
            onPressed: onChooseImage,
          ),
          if (scanSupported) ...[
            const SizedBox(height: 12),
            PrismButton(
              label: l10n.fieldTemplateImportScan,
              icon: AppIcons.qrCodeScanner,
              tone: PrismButtonTone.subtle,
              enabled: !busy,
              onPressed: onScan,
            ),
          ],
        ],
      ),
    );
  }
}

class _ScanView extends StatelessWidget {
  const _ScanView({
    required this.controller,
    required this.onDetect,
    required this.onBack,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: PrismButton(
              label: l10n.back,
              onPressed: onBack,
              icon: AppIcons.arrowBackIosNew,
              tone: PrismButtonTone.subtle,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.fieldTemplateImportScanDescription,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(16),
            ),
            child: SizedBox(
              height: 280,
              child: MobileScanner(controller: controller, onDetect: onDetect),
            ),
          ),
        ],
      ),
    );
  }
}
