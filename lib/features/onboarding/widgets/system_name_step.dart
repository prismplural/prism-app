import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';

class SystemNameStep extends ConsumerStatefulWidget {
  const SystemNameStep({super.key});

  @override
  ConsumerState<SystemNameStep> createState() => _SystemNameStepState();
}

class _SystemNameStepState extends ConsumerState<SystemNameStep> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final currentName = ref.read(onboardingProvider).systemName;
    _controller = TextEditingController(text: currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final autoFocus = !onboarding.wasImportedFromPluralKit;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _controller,
              autofocus: autoFocus,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'Enter system name',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
              ),
              onChanged: (value) {
                ref.read(onboardingProvider.notifier).setSystemName(value);
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'This is how your system will be identified in the app.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
