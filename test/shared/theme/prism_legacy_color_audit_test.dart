import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _legacyThemeFiles = {
  'lib/shared/theme/accent_legibility.dart',
  'lib/shared/theme/app_colors.dart',
  'lib/shared/theme/app_theme.dart',
};

const _allowedLegacyColorReferenceCounts = <String, int>{
  'lib/features/boards/views/boards_screen.dart': 9,
  'lib/features/chat/widgets/attachment_preview.dart': 2,
  'lib/features/chat/widgets/chat_markdown_editing_controller.dart': 1,
  'lib/features/chat/widgets/media/gif_bubble.dart': 4,
  'lib/features/chat/widgets/media/image_bubble.dart': 4,
  'lib/features/chat/widgets/mention_overlay.dart': 5,
  'lib/features/chat/widgets/message_input.dart': 9,
  'lib/features/chat/widgets/reaction_bar.dart': 1,
  'lib/features/chat/widgets/voice_recorder.dart': 4,
  'lib/features/habits/widgets/habit_chip.dart': 1,
  'lib/features/habits/widgets/habit_row.dart': 1,
  'lib/features/onboarding/views/onboarding_screen.dart': 15,
  'lib/features/onboarding/widgets/add_members_step.dart': 24,
  'lib/features/onboarding/widgets/appearance_step.dart': 6,
  'lib/features/onboarding/widgets/biometric_setup_step.dart': 2,
  'lib/features/onboarding/widgets/chat_setup_step.dart': 36,
  'lib/features/onboarding/widgets/complete_step.dart': 2,
  'lib/features/onboarding/widgets/features_step.dart': 10,
  'lib/features/onboarding/widgets/fronting_defaults_step.dart': 6,
  'lib/features/onboarding/widgets/import_data_step.dart': 94,
  'lib/features/onboarding/widgets/live_count_card.dart': 6,
  'lib/features/onboarding/widgets/onboarding_data_ready_view.dart': 6,
  'lib/features/onboarding/widgets/phase_segments.dart': 2,
  'lib/features/onboarding/widgets/prism_shimmer_bar.dart': 5,
  'lib/features/onboarding/widgets/sync_device_step.dart': 20,
  'lib/features/onboarding/widgets/system_name_step.dart': 6,
  'lib/features/onboarding/widgets/terminology_step.dart': 14,
  'lib/features/onboarding/widgets/welcome_step.dart': 2,
  'lib/features/onboarding/widgets/whos_fronting_step.dart': 8,
  'lib/features/settings/views/accent_color_picker.dart': 1,
  'lib/features/settings/widgets/secret_key_reveal_content.dart': 1,
  'lib/shared/widgets/markdown_editing_controller.dart': 1,
  'lib/shared/widgets/prism_dialog.dart': 2,
  'lib/shared/widgets/prism_mnemonic_field.dart': 2,
};

final _legacyColorReferencePattern = RegExp(
  r'\bAppColors\.(?:'
  r'warmWhite|warmBlack|warmOffWhite|'
  r'parchment|parchmentElevated|parchmentStrong|'
  r'charcoal|charcoalElevated|charcoalSurface|charcoalStrong|'
  r'oledSurface[0-9]'
  r')\b|'
  r'0xFFF1E7D6|0xFFE7DAC8|0xFFD9CAB6|'
  r'0xFF33302B|0xFF3B3732|0xFF423E38|0xFF4D4842|'
  r'0xFFF0EDE6|0xFF4A4540|0xFFFAF4EA|'
  r'0xFF1A1612|0xFF211D17|0xFF292420|0xFF312B25',
);

void main() {
  test(
    'does not introduce new legacy Prism color references in production code',
    () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      final actualCounts = <String, int>{};
      final overBudget = <String>[];
      final staleBaseline = <String>[];

      for (final file in files) {
        final path = file.path.replaceAll('\\', '/');
        if (_legacyThemeFiles.contains(path)) continue;

        final count = _legacyColorReferencePattern
            .allMatches(file.readAsStringSync())
            .length;
        if (count == 0) continue;

        actualCounts[path] = count;
        final allowed = _allowedLegacyColorReferenceCounts[path] ?? 0;
        if (count > allowed) {
          overBudget.add('$path: $count found, $allowed allowed');
        }
      }

      for (final entry in _allowedLegacyColorReferenceCounts.entries) {
        final actual = actualCounts[entry.key] ?? 0;
        if (actual < entry.value) {
          staleBaseline.add(
            '${entry.key}: $actual found, ${entry.value} allowed',
          );
        }
      }

      expect(
        overBudget,
        isEmpty,
        reason:
            'Use Theme.of(context).colorScheme / semantic theme tokens instead '
            'of legacy Prism warm/parchment/charcoal colors. Existing references '
            'are tracked as a cleanup baseline; do not add new ones.',
      );

      expect(
        staleBaseline,
        isEmpty,
        reason:
            'A legacy Prism color reference was removed. Lower the cleanup '
            'baseline so this audit keeps ratcheting toward zero.',
      );
    },
  );
}
