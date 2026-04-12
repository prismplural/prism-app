import 'dart:math';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// Onboarding step that verifies the user has written down their recovery phrase
/// by asking them to select 3 specific words from multiple-choice options.
class ConfirmPhraseStep extends StatefulWidget {
  const ConfirmPhraseStep({
    super.key,
    required this.words,
    required this.onConfirmed,
  });

  /// All 12 BIP39 recovery words.
  final List<String> words;

  /// Called when the user has correctly identified all 3 challenge words.
  final VoidCallback onConfirmed;

  @override
  State<ConfirmPhraseStep> createState() => _ConfirmPhraseStepState();
}

class _ConfirmPhraseStepState extends State<ConfirmPhraseStep>
    with SingleTickerProviderStateMixin {
  late final List<int> _challengeIndices;
  late final List<List<String>> _optionsPerBlank;

  // Index into _challengeIndices for the currently active blank (0, 1, or 2).
  int _currentBlank = 0;

  // Which blanks have been answered correctly.
  final Set<int> _answered = {};

  // The most recently incorrect choice (per blank reset on next attempt).
  String? _wrongChoice;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();

    // Deterministic blank selection: seed with words hash for test stability.
    final rng = Random(widget.words.join('').hashCode);
    final allIndices = List.generate(widget.words.length, (i) => i);
    allIndices.shuffle(rng);
    _challengeIndices = allIndices.take(3).toList()..sort();

    // For each blank build 4 choices: correct + 3 random distractors, shuffled.
    _optionsPerBlank = _challengeIndices.map((correctIdx) {
      final distractors = List<int>.from(allIndices)..remove(correctIdx);
      distractors.shuffle(rng);
      final choices = [
        widget.words[correctIdx],
        ...distractors.take(3).map((i) => widget.words[i]),
      ]..shuffle(rng);
      return choices;
    }).toList();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  bool get _allAnswered => _answered.length == 3;

  void _onChoice(int blankIndex, String chosen) {
    final correctIdx = _challengeIndices[blankIndex];
    final correct = widget.words[correctIdx];

    if (chosen == correct) {
      setState(() {
        _wrongChoice = null;
        _answered.add(blankIndex);
        // Advance to the next unanswered blank.
        for (var i = 0; i < 3; i++) {
          if (!_answered.contains(i)) {
            _currentBlank = i;
            break;
          }
        }
      });
    } else {
      setState(() => _wrongChoice = chosen);
      _shakeController.forward(from: 0);
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
          // Progress row: 3 circles showing completion.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final done = _answered.contains(i);
              final active = i == _currentBlank && !done;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done
                        ? theme.colorScheme.primary
                        : active
                            ? theme.colorScheme.primary.withValues(alpha: 0.4)
                            : theme.colorScheme.onSurface.withValues(alpha: 0.15),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          if (!_allAnswered) ...[
            _BlankChallenge(
              blankIndex: _currentBlank,
              wordPosition: _challengeIndices[_currentBlank] + 1,
              options: _optionsPerBlank[_currentBlank],
              correctWord: widget.words[_challengeIndices[_currentBlank]],
              wrongChoice: _wrongChoice,
              shakeAnimation: _shakeAnimation,
              onChoice: (choice) => _onChoice(_currentBlank, choice),
            ),
          ] else ...[
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Phrase verified',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 32),
          PrismButton(
            label: 'Continue',
            onPressed: widget.onConfirmed,
            enabled: _allAnswered,
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
        ],
      ),
    );
  }
}

class _BlankChallenge extends StatelessWidget {
  const _BlankChallenge({
    required this.blankIndex,
    required this.wordPosition,
    required this.options,
    required this.correctWord,
    required this.wrongChoice,
    required this.shakeAnimation,
    required this.onChoice,
  });

  final int blankIndex;
  final int wordPosition;
  final List<String> options;
  final String correctWord;
  final String? wrongChoice;
  final Animation<double> shakeAnimation;
  final void Function(String choice) onChoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select word #$wordPosition',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: shakeAnimation,
          builder: (context, child) => Transform.translate(
            offset: Offset(shakeAnimation.value, 0),
            child: child,
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: options.map((option) {
              final isWrong = option == wrongChoice;
              return _ChoiceChip(
                label: option,
                isWrong: isWrong,
                onTap: () => onChoice(option),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.isWrong,
    required this.onTap,
  });

  final String label;
  final bool isWrong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final backgroundColor = isWrong
        ? theme.colorScheme.error.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7);

    final borderColor = isWrong
        ? theme.colorScheme.error.withValues(alpha: 0.4)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

    final textColor = isWrong
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: backgroundColor,
          border: Border.all(color: borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
