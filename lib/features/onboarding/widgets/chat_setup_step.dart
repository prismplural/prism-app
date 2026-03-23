import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';

class ChatSetupStep extends ConsumerStatefulWidget {
  const ChatSetupStep({super.key});

  @override
  ConsumerState<ChatSetupStep> createState() => _ChatSetupStepState();
}

class _ChatSetupStepState extends ConsumerState<ChatSetupStep> {
  final _customChannelController = TextEditingController();

  static const _suggestedChannels = {
    'All Members': '\u{1F465}',
    'Venting': '\u{1F62E}\u200D\u{1F4A8}',
    'Planning': '\u{1F4CB}',
    'Journal': '\u{1F4D3}',
    'Updates': '\u{1F4E2}',
    'Random': '\u{1F3B2}',
  };

  @override
  void dispose() {
    _customChannelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Suggested Channels',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),

          // Suggested channels
          ..._suggestedChannels.entries.map((entry) {
            final isSelected =
                onboarding.selectedChannels.containsKey(entry.key);
            final isAllMembers = entry.key == 'All Members';

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: isAllMembers
                    ? null
                    : () => notifier.toggleChannel(entry.key, entry.value),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text(entry.value, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isAllMembers)
                        Icon(
                          Icons.lock,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.4),
                        )
                      else
                        Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: isSelected
                              ? Colors.cyan
                              : Colors.white.withValues(alpha: 0.3),
                          size: 22,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 20),

          // Custom channel section
          Text(
            'Custom Channel',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextField(
                    controller: _customChannelController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Channel name',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  final name = _customChannelController.text.trim();
                  if (name.isNotEmpty) {
                    notifier.addCustomChannel(name, '\u{1F4AC}');
                    _customChannelController.clear();
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 22),
                ),
              ),
            ],
          ),

          // Show custom channels added
          if (onboarding.selectedChannels.keys
              .where((k) => !_suggestedChannels.containsKey(k))
              .isNotEmpty) ...[
            const SizedBox(height: 12),
            ...onboarding.selectedChannels.entries
                .where((e) => !_suggestedChannels.containsKey(e.key))
                .map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Text(entry.value,
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => notifier.toggleChannel(
                                  entry.key, entry.value),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
          ],
        ],
      ),
    );
  }
}
