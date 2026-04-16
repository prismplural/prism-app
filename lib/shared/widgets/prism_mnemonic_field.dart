import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:prism_plurality/core/crypto/bip39_english_wordlist.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/glass_surface.dart';

/// A reusable 12-word BIP39 recovery phrase input.
///
/// Features:
///  - Multiline textarea (caller-owned controller).
///  - Live 12-slot word-chip grid below the field that shows which slots
///    are filled and whether each filled word is a valid BIP39 word.
///  - Clipboard paste button that appears only when the clipboard holds
///    exactly 12 whitespace-separated BIP39 words.
///  - Visibility toggle that flips [obscureText] on the underlying field.
///    Default: visible, because recovery UX is "cross-reference my
///    external copy" not "type my password".
///  - Horizontal BIP39 autocomplete strip of [GlassSurface] chips for the
///    current partial word; tapping a chip inserts `"$word "` and
///    advances the caret.
///
/// The widget never persists the entered text. Callers are responsible
/// for clearing their controller in `dispose()`.
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
  final String? hintText;

  /// Normalize raw user input to the canonical BIP39 form:
  /// trimmed, lowercased, and single-space-delimited.
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
  late final FocusNode _focusNode;
  bool _obscure = false;
  bool _hasValidClipboard = false;

  // Wordlist as a Set for O(1) membership checks.
  static final Set<String> _wordSet = bip39EnglishWordlistSet;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChanged);
    // Seed clipboard detection. We don't poll aggressively — just on
    // focus-in and when the app comes back to the foreground (handled
    // by WidgetsBindingObserver; for now, check once on init).
    _refreshClipboard();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _refreshClipboard();
    }
    // Rebuild so the autocomplete strip reflects focus state.
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {});
  }

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
      final isValid = tokens.length == 12 &&
          tokens.every(_wordSet.contains);
      if (!mounted) return;
      if (isValid != _hasValidClipboard) {
        setState(() => _hasValidClipboard = isValid);
      }
    } catch (_) {
      // Platforms without clipboard support — just hide the button.
      if (mounted && _hasValidClipboard) {
        setState(() => _hasValidClipboard = false);
      }
    }
  }

  List<String> get _tokens {
    final text = widget.controller.text;
    if (text.isEmpty) return const [];
    return text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
  }

  int get _validCount {
    var count = 0;
    for (final t in _tokens) {
      if (_wordSet.contains(t)) count++;
      if (count >= 12) break;
    }
    return count;
  }

  /// The partial word currently under the caret. Returns empty string
  /// when there's no active partial (e.g. caret follows a space).
  String _currentPartial() {
    final selection = widget.controller.selection;
    final text = widget.controller.text;
    final caret = selection.isValid ? selection.baseOffset : text.length;
    if (caret <= 0) return '';
    final upToCaret = text.substring(0, caret).toLowerCase();
    // Look backward for the start of the current token.
    final idx = upToCaret.lastIndexOf(RegExp(r'\s'));
    final partial = upToCaret.substring(idx + 1);
    return partial;
  }

  List<String> _suggestionsFor(String partial) {
    if (partial.isEmpty) return const [];
    // Skip if the partial is itself a valid word — the user has typed
    // it in full and probably doesn't want to re-insert it.
    if (_wordSet.contains(partial)) return const [];
    final hits = <String>[];
    for (final w in bip39EnglishWordlist) {
      if (w.startsWith(partial)) {
        hits.add(w);
        if (hits.length >= 5) break;
      }
    }
    return hits;
  }

  Future<void> _handlePaste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      final normalized = PrismMnemonicField.normalize(text);
      final tokens = normalized.split(' ');
      if (tokens.length != 12 || !tokens.every(_wordSet.contains)) {
        // Shouldn't happen — button only appears when clipboard is valid.
        return;
      }
      Haptics.selection();
      widget.controller.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
      widget.onSubmitted?.call(normalized);
    } catch (_) {
      // Swallow — nothing user-visible to do.
    }
  }

  void _toggleObscure() {
    Haptics.selection();
    setState(() => _obscure = !_obscure);
  }

  void _insertSuggestion(String word) {
    final partial = _currentPartial();
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final caret = selection.isValid ? selection.baseOffset : text.length;
    // Replace the partial token at the caret with "$word ".
    final replaceStart = caret - partial.length;
    final before = text.substring(0, replaceStart);
    final after = text.substring(caret);
    final insert = '$word ';
    final newText = '$before$insert$after';
    final newCaret = replaceStart + insert.length;
    Haptics.selection();
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCaret),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final tokens = _tokens;
    final validCount = _validCount;
    final partial = _currentPartial();
    final suggestions = _focusNode.hasFocus ? _suggestionsFor(partial) : const <String>[];
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final counterColor = validCount == 12
        ? Colors.green
        : theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header ──────────────────────────────────────────────────────
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
        const SizedBox(height: 8),

        // ── Textarea ────────────────────────────────────────────────────
        _MnemonicTextField(
          controller: widget.controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          obscureText: _obscure,
          hintText: widget.hintText,
          hasError: hasError,
          onSubmitted: (v) => widget.onSubmitted?.call(v),
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

        // ── Chip grid ───────────────────────────────────────────────────
        const SizedBox(height: 12),
        _WordChipGrid(
          tokens: tokens,
          wordSet: _wordSet,
        ),

        // ── Autocomplete strip ──────────────────────────────────────────
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final word = suggestions[i];
                return _SuggestionChip(
                  word: word,
                  onTap: () => _insertSuggestion(word),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Private support widgets
// ─────────────────────────────────────────────────────────────────────────

class _MnemonicTextField extends StatelessWidget {
  const _MnemonicTextField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.autofocus,
    required this.obscureText,
    required this.hasError,
    required this.onSubmitted,
    this.hintText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool autofocus;
  final bool obscureText;
  final bool hasError;
  final String? hintText;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;
    final radius = BorderRadius.circular(PrismTokens.radiusMedium);
    final border = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(
        color: hasError
            ? errorColor.withValues(alpha: 0.35)
            : theme.colorScheme.outlineVariant,
      ),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(
        color: hasError ? errorColor : theme.colorScheme.primary,
        width: 1.4,
      ),
    );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscureText,
      // Disable iOS autocorrect + suggestions and Android predictive.
      keyboardType: TextInputType.visiblePassword,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      minLines: obscureText ? 1 : 3,
      maxLines: obscureText ? 1 : 5,
      style: theme.textTheme.bodyLarge,
      cursorColor: theme.colorScheme.primary,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: hasError
            ? errorColor.withValues(alpha: 0.06)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: border,
        enabledBorder: border,
        focusedBorder: focusedBorder,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }
}

class _WordChipGrid extends StatelessWidget {
  const _WordChipGrid({required this.tokens, required this.wordSet});

  final List<String> tokens;
  final Set<String> wordSet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <Widget>[];
    for (var i = 0; i < 12; i++) {
      final word = i < tokens.length ? tokens[i] : null;
      final slotNum = i + 1;
      if (word == null) {
        chips.add(_EmptySlotChip(slotNumber: slotNum));
      } else {
        final isValid = wordSet.contains(word);
        chips.add(_FilledChip(
          slotNumber: slotNum,
          word: word,
          isValid: isValid,
          theme: theme,
        ));
      }
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }
}

class _EmptySlotChip extends StatelessWidget {
  const _EmptySlotChip({required this.slotNumber});

  final int slotNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.6);
    return Semantics(
      label: context.l10n.mnemonicFieldWordSlotLabel(slotNumber.toString()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PrismTokens.radiusPill),
          border: Border.all(
            color: borderColor,
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Text(
          '$slotNumber',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _FilledChip extends StatelessWidget {
  const _FilledChip({
    required this.slotNumber,
    required this.word,
    required this.isValid,
    required this.theme,
  });

  final int slotNumber;
  final String word;
  final bool isValid;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final primary = theme.colorScheme.primary;
    final error = theme.colorScheme.error;
    final tint = isValid ? primary : error;
    return Semantics(
      label: isValid
          ? context.l10n.mnemonicFieldWordChipValid(slotNumber.toString(), word)
          : context.l10n
              .mnemonicFieldWordChipInvalid(slotNumber.toString(), word),
      child: GlassSurface(
        tint: tint,
        borderRadius: BorderRadius.circular(PrismTokens.radiusPill),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$slotNumber',
              style: theme.textTheme.labelSmall?.copyWith(
                color: tint.withValues(alpha: 0.7),
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              word,
              style: theme.textTheme.labelMedium?.copyWith(
                color: isValid
                    ? theme.colorScheme.onSurface
                    : error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
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
      borderRadius: BorderRadius.circular(PrismTokens.radiusPill),
      child: GlassSurface(
        tint: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(PrismTokens.radiusPill),
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
