import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// Onboarding step that displays the 12-word BIP39 recovery phrase.
///
/// The phrase is shown blurred by default. The user must explicitly
/// tap to reveal it, confirming they understand the importance of saving it.
/// Tapping [onContinue] advances to the phrase confirmation step.
class RecoveryPhraseStep extends StatefulWidget {
  const RecoveryPhraseStep({
    super.key,
    required this.words,
    required this.onContinue,
  });

  /// The 12 mnemonic words to display.
  final List<String> words;

  /// Called when the user taps "I've saved it".
  final VoidCallback onContinue;

  @override
  State<RecoveryPhraseStep> createState() => _RecoveryPhraseStepState();
}

class _RecoveryPhraseStepState extends State<RecoveryPhraseStep> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = theme.colorScheme.primary;

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // Warning banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber.shade700, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Write these down. You cannot recover your data without them.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? Colors.amber.shade200
                              : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Word grid
              GestureDetector(
                onTap: () => setState(() => _revealed = !_revealed),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: 1.0,
                  child: Stack(
                    children: [
                      // Word grid (always rendered, blurred when hidden)
                      _WordGrid(words: widget.words, isDark: isDark),
                      // Blur overlay
                      if (!_revealed)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.7)
                                  : Colors.white.withValues(alpha: 0.85),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.visibility_outlined,
                                        size: 36,
                                        color: accentColor),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Tap to reveal',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        color: accentColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_revealed) ...[
                const SizedBox(height: 12),
                // Copy button
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: widget.words.join(' ')),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Recovery phrase copied'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Copy to clipboard'),
                ),
              ],
              const SizedBox(height: 24),
              PrismButton(
                label: "I've saved it — continue",
                onPressed: widget.onContinue,
                enabled: _revealed,
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

class _WordGrid extends StatelessWidget {
  const _WordGrid({required this.words, required this.isDark});

  final List<String> words;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.warmWhite.withValues(alpha: 0.07)
            : AppColors.warmBlack.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? AppColors.warmWhite.withValues(alpha: 0.12)
              : AppColors.warmBlack.withValues(alpha: 0.08),
        ),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 2.4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: words.length,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.08)
                  : AppColors.warmBlack.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${index + 1}.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    words[index],
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      overflow: TextOverflow.ellipsis,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
