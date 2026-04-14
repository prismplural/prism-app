import 'package:flutter/material.dart';
import 'package:prism_plurality/features/settings/widgets/secret_key_reveal_content.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// Onboarding step that displays the 12-word BIP39 recovery phrase using
/// [SecretKeyRevealContent] (copy, share, QR code) with a checkbox gate.
///
/// Replaces the old blur-to-reveal [RecoveryPhraseStep] and quiz
/// [ConfirmPhraseStep] with a single, clearer step.
class RecoveryPhraseOnboardingStep extends StatefulWidget {
  const RecoveryPhraseOnboardingStep({
    super.key,
    required this.words,
    required this.onContinue,
  });

  /// The 12 BIP39 recovery words.
  final List<String> words;

  /// Called when the user confirms they have saved the phrase.
  final VoidCallback onContinue;

  @override
  State<RecoveryPhraseOnboardingStep> createState() =>
      _RecoveryPhraseOnboardingStepState();
}

class _RecoveryPhraseOnboardingStepState
    extends State<RecoveryPhraseOnboardingStep> {
  bool _hasSaved = false;
  late final String _mnemonic;

  @override
  void initState() {
    super.initState();
    _mnemonic = widget.words.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: SecretKeyRevealContent(
                mnemonic: _mnemonic,
                hasSaved: _hasSaved,
                onHasSavedChanged: (v) => setState(() => _hasSaved = v),
                requireInteraction: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
          PrismButton(
            label: 'Continue',
            onPressed: widget.onContinue,
            enabled: _hasSaved,
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
