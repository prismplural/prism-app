import 'dart:math';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// Onboarding step that verifies the user saved their recovery phrase.
///
/// Selects 3 random word positions and prompts the user to enter the
/// correct words. Advances via [onConfirmed] only when all 3 are correct.
class ConfirmPhraseStep extends StatefulWidget {
  const ConfirmPhraseStep({
    super.key,
    required this.words,
    required this.onConfirmed,
  });

  /// The full 12-word mnemonic list to verify against.
  final List<String> words;

  /// Called when the user correctly fills all 3 word slots.
  final VoidCallback onConfirmed;

  @override
  State<ConfirmPhraseStep> createState() => _ConfirmPhraseStepState();
}

class _ConfirmPhraseStepState extends State<ConfirmPhraseStep> {
  late List<int> _indicesToVerify;
  late List<TextEditingController> _controllers;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _pickIndices();
    _controllers = List.generate(3, (_) => TextEditingController());
  }

  void _pickIndices() {
    final rng = Random();
    final indices = <int>{};
    while (indices.length < 3) {
      indices.add(rng.nextInt(widget.words.length));
    }
    _indicesToVerify = indices.toList()..sort();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _verify() {
    final allCorrect = List.generate(3, (i) {
      final entered = _controllers[i].text.trim().toLowerCase();
      final expected = widget.words[_indicesToVerify[i]].toLowerCase();
      return entered == expected;
    }).every((ok) => ok);

    if (allCorrect) {
      widget.onConfirmed();
    } else {
      setState(() => _hasError = true);
      for (final c in _controllers) {
        c.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                'Enter words at positions:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              for (var i = 0; i < 3; i++) ...[
                _WordSlot(
                  position: _indicesToVerify[i] + 1,
                  controller: _controllers[i],
                  hasError: _hasError,
                  onSubmitted: i == 2 ? (_) => _verify() : null,
                ),
                if (i < 2) const SizedBox(height: 16),
              ],
              if (_hasError) ...[
                const SizedBox(height: 16),
                Text(
                  'Some words were incorrect. Try again.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              PrismButton(
                label: 'Verify',
                onPressed: _verify,
                expanded: true,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordSlot extends StatelessWidget {
  const _WordSlot({
    required this.position,
    required this.controller,
    required this.hasError,
    this.onSubmitted,
  });

  final int position;
  final TextEditingController controller;
  final bool hasError;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      textInputAction:
          onSubmitted != null ? TextInputAction.done : TextInputAction.next,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: 'Word #$position',
        errorText: hasError ? ' ' : null, // Reserve space but show no message
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      style: theme.textTheme.bodyLarge,
    );
  }
}
