import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:prism_plurality/core/crypto/bip39_english_wordlist.dart';
import 'package:prism_plurality/core/crypto/bip39_validate.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/glass_surface.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';

/// A 12-word BIP39 recovery phrase input rendered as a 2×6 grid of individual
/// word slots. Focuses automatically advance slot-to-slot on space or suggestion
/// tap; backspace on an empty slot returns to the previous one.
///
/// Suggestion chips float above the keyboard via [OverlayPortal], positioned
/// using [MediaQuery.viewInsetsOf] so they're always visible while typing.
class PrismMnemonicField extends StatefulWidget {
  const PrismMnemonicField({
    super.key,
    required this.controller,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.onSubmitted,
    this.hintText,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  /// Unused in the grid layout; kept for API compatibility.
  final String? hintText;

  /// Normalize raw user input to canonical BIP39 form:
  /// trimmed, lowercased, single-space-delimited.
  static String normalize(String raw) => raw
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .join(' ');

  @override
  State<PrismMnemonicField> createState() => _PrismMnemonicFieldState();
}

class _PrismMnemonicFieldState extends State<PrismMnemonicField> {
  final List<TextEditingController> _slotControllers = List.generate(
    12,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _slotFocusNodes = List.generate(12, (_) => FocusNode());
  final _overlayController = OverlayPortalController();

  int _focusedSlot = -1;
  bool _obscure = false;
  bool _hasValidClipboard = false;
  bool _syncingToExternal = false;
  bool _syncingFromExternal = false;

  static final Set<String> _wordSet = bip39EnglishWordlistSet;

  String? _validatedMnemonic([String? raw]) {
    final normalized = PrismMnemonicField.normalize(
      raw ?? widget.controller.text,
    );
    final words = normalized.split(' ');
    if (words.length != 12 || !validateBip39Mnemonic(normalized)) {
      return null;
    }
    return normalized;
  }

  @override
  void initState() {
    super.initState();
    _syncSlotsFromController();
    widget.controller.addListener(_onExternalControllerChanged);
    for (var i = 0; i < 12; i++) {
      final index = i;
      _slotFocusNodes[i].addListener(() => _onSlotFocusChanged(index));
      _slotFocusNodes[i].onKeyEvent = (_, event) =>
          _handleKeyEvent(index, event);
    }
    _refreshClipboard();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternalControllerChanged);
    for (final c in _slotControllers) {
      c.dispose();
    }
    for (final f in _slotFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // ── Sync ─────────────────────────────────────────────────────────────────

  void _syncSlotsFromController() {
    final text = widget.controller.text;
    final tokens = text.isEmpty
        ? <String>[]
        : text
              .trim()
              .toLowerCase()
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .toList();
    for (var i = 0; i < 12; i++) {
      final word = i < tokens.length ? tokens[i] : '';
      if (_slotControllers[i].text != word) _slotControllers[i].text = word;
    }
  }

  void _onExternalControllerChanged() {
    if (_syncingToExternal || !mounted) return;
    _syncingFromExternal = true;
    _syncSlotsFromController();
    _syncingFromExternal = false;
    setState(() {});
  }

  void _syncToExternalController() {
    if (_syncingFromExternal) return;
    _syncingToExternal = true;
    final words = _slotControllers
        .map((c) => c.text.trim().toLowerCase())
        .where((w) => w.isNotEmpty)
        .join(' ');
    widget.controller.value = TextEditingValue(
      text: words,
      selection: TextSelection.collapsed(offset: words.length),
    );
    _syncingToExternal = false;
  }

  // ── Focus ─────────────────────────────────────────────────────────────────

  void _onSlotFocusChanged(int index) {
    final hasFocus = _slotFocusNodes[index].hasFocus;
    setState(() {
      if (hasFocus) {
        _focusedSlot = index;
      } else if (_focusedSlot == index) {
        _focusedSlot = -1;
      }
    });
    _syncOverlay();
    if (hasFocus) _refreshClipboard();
  }

  void _moveFocusToSlot(int index) {
    if (index < 0 || index >= 12) return;
    // Defer to next frame so the keyboard stays visible during the transition.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _slotFocusNodes[index].requestFocus();
      final text = _slotControllers[index].text;
      _slotControllers[index].selection = TextSelection.collapsed(
        offset: text.length,
      );
    });
  }

  KeyEventResult _handleKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _slotControllers[index].text.isEmpty &&
        index > 0) {
      _moveFocusToSlot(index - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Input handling ────────────────────────────────────────────────────────

  void _onSlotChanged(int index, String value) {
    final hasSpaces = value.contains(' ') || value.contains('\n');
    if (hasSpaces) {
      final parts = value
          .split(RegExp(r'[\s\n]+'))
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.length > 1) {
        // Multi-word paste — distribute across subsequent slots.
        for (var i = 0; i < parts.length && (index + i) < 12; i++) {
          _slotControllers[index + i].text = parts[i];
        }
        _syncToExternalController();
        _moveFocusToSlot((index + parts.length).clamp(0, 11));
        final allValid = _slotControllers.every(
          (c) => _wordSet.contains(c.text),
        );
        if (allValid) widget.onSubmitted?.call(widget.controller.text);
      } else {
        // Single word with trailing space — advance to next slot.
        _slotControllers[index].text = parts.isEmpty ? '' : parts[0];
        _syncToExternalController();
        if (parts.isNotEmpty) _moveFocusToSlot(index + 1);
      }
      setState(() {});
      _syncOverlay();
      return;
    }

    // Normal typing — formatter already lowercased and length-capped the value.
    _syncToExternalController();
    setState(() {});
    _syncOverlay();
  }

  void _insertSuggestion(int slotIndex, String word) {
    Haptics.selection();
    _slotControllers[slotIndex].text = word;
    _syncToExternalController();
    if (slotIndex < 11) {
      _moveFocusToSlot(slotIndex + 1);
    } else {
      widget.onSubmitted?.call(widget.controller.text);
    }
    setState(() {});
    _syncOverlay();
  }

  // ── Overlay management ────────────────────────────────────────────────────

  void _syncOverlay() {
    final hasSuggestions =
        _focusedSlot >= 0 && _suggestionsFor(_focusedSlot).isNotEmpty;
    if (hasSuggestions) {
      _overlayController.show();
    } else {
      if (_overlayController.isShowing) _overlayController.hide();
    }
  }

  // ── Suggestions ───────────────────────────────────────────────────────────

  List<String> _suggestionsFor(int slotIndex) {
    if (slotIndex < 0 || slotIndex >= 12) return const [];
    final partial = _slotControllers[slotIndex].text.trim().toLowerCase();
    if (partial.isEmpty || _wordSet.contains(partial)) return const [];
    final hits = <String>[];
    for (final w in bip39EnglishWordlist) {
      if (w.startsWith(partial)) {
        hits.add(w);
        if (hits.length >= 6) break;
      }
    }
    return hits;
  }

  // ── Clipboard ─────────────────────────────────────────────────────────────

  Future<void> _refreshClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      final tokens = text
          .trim()
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList(growable: false);
      final isValid = tokens.length == 12 && tokens.every(_wordSet.contains);
      if (!mounted) return;
      if (isValid != _hasValidClipboard) {
        setState(() => _hasValidClipboard = isValid);
      }
    } catch (_) {
      if (mounted && _hasValidClipboard) {
        setState(() => _hasValidClipboard = false);
      }
    }
  }

  Future<void> _handlePaste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      final normalized = _validatedMnemonic(text);
      if (normalized == null) return;
      _applyMnemonic(normalized);
    } catch (_) {}
  }

  void _toggleObscure() {
    Haptics.selection();
    setState(() => _obscure = !_obscure);
  }

  void _applyMnemonic(String normalizedMnemonic) {
    final tokens = normalizedMnemonic.split(' ');
    if (tokens.length != 12) return;
    Haptics.selection();
    for (var i = 0; i < 12; i++) {
      _slotControllers[i].text = tokens[i];
    }
    _syncToExternalController();
    setState(() {});
    _syncOverlay();
    widget.onSubmitted?.call(widget.controller.text);
  }

  Future<void> _showQrCode() async {
    final normalized = _validatedMnemonic();
    if (normalized == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _MnemonicQrDialog(mnemonic: normalized),
    );
  }

  Future<void> _scanQrCode() async {
    if (!mounted) return;
    final scannedMnemonic = await showDialog<String>(
      context: context,
      builder: (context) => const _MnemonicQrScannerDialog(),
    );
    if (!mounted || scannedMnemonic == null) return;
    _applyMnemonic(scannedMnemonic);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final validCount = _slotControllers
        .where((c) => _wordSet.contains(c.text.trim()))
        .length;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final counterColor = validCount == 12
        ? Colors.green
        : theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final hasValidMnemonic = _validatedMnemonic() != null;

    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (context) {
        final slot = _focusedSlot;
        final suggestions = slot >= 0
            ? _suggestionsFor(slot)
            : const <String>[];
        final bottom = MediaQuery.viewInsetsOf(context).bottom;
        return Positioned(
          bottom: bottom,
          left: 0,
          right: 0,
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                itemCount: suggestions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _SuggestionChip(
                  word: suggestions[i],
                  onTap: () => _insertSuggestion(slot, suggestions[i]),
                ),
              ),
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (validCount == 12)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            AppIcons.checkCircle,
                            size: 18,
                            color: Colors.green,
                          ),
                        ),
                      Flexible(
                        child: Text(
                          l10n.mnemonicFieldWordCounter(validCount.toString()),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: counterColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_hasValidClipboard && widget.enabled)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    icon: Icon(AppIcons.paste, size: 20),
                    tooltip: l10n.mnemonicFieldPaste,
                    onPressed: _handlePaste,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  icon: Icon(AppIcons.qrCodeScanner, size: 20),
                  tooltip: 'Scan QR Code',
                  onPressed: widget.enabled ? _scanQrCode : null,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (hasValidMnemonic)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    icon: Icon(AppIcons.qrCode, size: 20),
                    tooltip: 'Show QR Code',
                    onPressed: widget.enabled ? _showQrCode : null,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              IconButton(
                icon: Icon(
                  _obscure
                      ? AppIcons.visibilityOffOutlined
                      : AppIcons.visibilityOutlined,
                  size: 20,
                ),
                tooltip: _obscure
                    ? l10n.mnemonicFieldShowWords
                    : l10n.mnemonicFieldHideWords,
                onPressed: widget.enabled ? _toggleObscure : null,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── 2×6 word input grid ────────────────────────────────────────────
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 40,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: 12,
            itemBuilder: (_, i) => _WordSlotInput(
              slotNumber: i + 1,
              controller: _slotControllers[i],
              focusNode: _slotFocusNodes[i],
              obscureText: _obscure,
              wordSet: _wordSet,
              enabled: widget.enabled,
              autofocus: widget.autofocus && i == 0,
              isLast: i == 11,
              onChanged: (v) => _onSlotChanged(i, v),
              onSubmitted: i < 11
                  ? (_) => _moveFocusToSlot(i + 1)
                  : (_) => widget.onSubmitted?.call(widget.controller.text),
            ),
          ),

          if (hasError) ...[
            const SizedBox(height: 6),
            Text(
              widget.errorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MnemonicQrDialog extends StatelessWidget {
  const _MnemonicQrDialog({required this.mnemonic});

  final String mnemonic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SecureScope(
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Recovery Phrase QR',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Scan this QR code to fill the 12-word recovery phrase on another device.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.warmWhite,
                    borderRadius: BorderRadius.circular(
                      PrismShapes.of(context).radius(16),
                    ),
                  ),
                  child: QrImageView(
                    data: mnemonic,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: AppColors.warmWhite,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MnemonicQrScannerDialog extends StatefulWidget {
  const _MnemonicQrScannerDialog();

  @override
  State<_MnemonicQrScannerDialog> createState() =>
      _MnemonicQrScannerDialogState();
}

class _MnemonicQrScannerDialogState extends State<_MnemonicQrScannerDialog> {
  final _controller = MobileScannerController();
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null) return;

    final normalized = PrismMnemonicField.normalize(rawValue);
    final words = normalized.split(' ');
    if (words.length != 12 || !validateBip39Mnemonic(normalized)) {
      setState(() {
        _error = 'Invalid QR code. Scan a 12-word recovery phrase.';
      });
      return;
    }

    _handled = true;
    Navigator.of(context).pop(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SecureScope(
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Scan Recovery QR',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Scan a QR code that contains your 12-word recovery phrase.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(16),
                ),
                child: SizedBox(
                  height: 280,
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Single numbered word slot: slot label + single-line TextField.
class _WordSlotInput extends StatelessWidget {
  const _WordSlotInput({
    required this.slotNumber,
    required this.controller,
    required this.focusNode,
    required this.obscureText,
    required this.wordSet,
    required this.enabled,
    required this.autofocus,
    required this.isLast,
    required this.onChanged,
    required this.onSubmitted,
  });

  final int slotNumber;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscureText;
  final Set<String> wordSet;
  final bool enabled;
  final bool autofocus;
  final bool isLast;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = PrismShapes.of(context).radius(PrismTokens.radiusSmall);
    final word = controller.text.trim().toLowerCase();
    final hasContent = word.isNotEmpty;
    final isValid = hasContent && wordSet.contains(word);
    final isInvalid = hasContent && !isValid;

    final borderColor = isInvalid ? theme.colorScheme.error : null;
    final fillColor = isValid
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);

    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(
        color:
            borderColor ??
            theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
      ),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(
        color: borderColor ?? theme.colorScheme.primary,
        width: 1.4,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 18,
          child: Text(
            '$slotNumber',
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            autofocus: autofocus,
            obscureText: obscureText,
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            maxLines: 1,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            textInputAction: isLast
                ? TextInputAction.done
                : TextInputAction.next,
            style: theme.textTheme.bodyMedium,
            cursorColor: theme.colorScheme.primary,
            inputFormatters: [_WordInputFormatter()],
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              filled: true,
              fillColor: fillColor,
              border: baseBorder,
              enabledBorder: baseBorder,
              focusedBorder: focusedBorder,
            ),
          ),
        ),
      ],
    );
  }
}

/// Lowercases input and limits length to 8 chars (max BIP39 word length)
/// unless the value contains spaces (multi-word paste), in which case length
/// limiting is skipped so the parent can distribute the words across slots.
class _WordInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final lower = newValue.copyWith(text: newValue.text.toLowerCase());
    if (lower.text.contains(' ') || lower.text.contains('\n')) return lower;
    if (lower.text.length > 8) {
      return lower.copyWith(
        text: lower.text.substring(0, 8),
        selection: const TextSelection.collapsed(offset: 8),
      );
    }
    return lower;
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.word, required this.onTap});

  final String word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        PrismShapes.of(context).radius(PrismTokens.radiusPill),
      ),
      child: GlassSurface(
        tint: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(PrismTokens.radiusPill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          word,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
