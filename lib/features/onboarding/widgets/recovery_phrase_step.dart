import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// Onboarding step that displays a 12-word BIP39 recovery phrase.
///
/// Words are blurred by default. The user must tap to reveal them before the
/// "I've written it down" button becomes enabled.
class RecoveryPhraseStep extends StatefulWidget {
  const RecoveryPhraseStep({
    super.key,
    required this.words,
    required this.onContinue,
  });

  /// The 12 BIP39 recovery words.
  final List<String> words;

  /// Called when the user confirms they have written down the phrase.
  final VoidCallback onContinue;

  @override
  State<RecoveryPhraseStep> createState() => _RecoveryPhraseStepState();
}

class _RecoveryPhraseStepState extends State<RecoveryPhraseStep> {
  bool _revealed = false;

  void _reveal() {
    setState(() => _revealed = true);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.words.join(' ')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recovery phrase copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _WordGrid(
            words: widget.words,
            revealed: _revealed,
            onReveal: _reveal,
          ),
          const SizedBox(height: 20),
          if (_revealed) ...[
            TextButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copy to clipboard'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                textStyle: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),
          ],
          PrismButton(
            label: "I've written it down",
            onPressed: widget.onContinue,
            enabled: _revealed,
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
        ],
      ),
    );
  }
}

class _WordGrid extends StatelessWidget {
  const _WordGrid({
    required this.words,
    required this.revealed,
    required this.onReveal,
  });

  final List<String> words;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 3 columns × 4 rows of numbered word chips.
    final grid = GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: words.length,
      itemBuilder: (context, index) {
        final n = index + 1;
        final word = words[index];
        return Semantics(
          label: revealed ? 'Word $n of 12: $word' : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    word,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (revealed) {
      return grid;
    }

    // Blurred overlay until revealed.
    return GestureDetector(
      onTap: onReveal,
      child: Semantics(
        label: 'Recovery phrase hidden. Tap to reveal.',
        child: Stack(
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: grid,
            ),
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 28,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to reveal',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
