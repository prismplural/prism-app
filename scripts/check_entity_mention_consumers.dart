import 'dart:io';

typedef Check = ({String path, List<String> mustContain});

const checks = <Check>[
  (
    path: 'lib/features/members/views/member_detail_screen.dart',
    mustContain: ['EntityMentionMarkdownText', 'openProfileEntityMention'],
  ),
  (
    path: 'lib/features/members/views/add_edit_member_sheet.dart',
    mustContain: [
      'EntityMentionEditingController',
      'EntityMentionTextField',
      'entityMentionsEnabled: true',
    ],
  ),
  (
    path: 'lib/features/members/widgets/custom_fields_editor.dart',
    mustContain: [
      'EntityMentionEditingController',
      'EntityMentionTextField',
      'entityMentionsEnabled: true',
    ],
  ),
  (
    path: 'lib/features/members/widgets/custom_fields_display.dart',
    mustContain: [
      'EntityMentionInlineText',
      'EntityMentionMarkdownText',
      'openProfileEntityMention',
      '_safeSubstringWithoutSplittingMention',
    ],
  ),
  (
    path: 'lib/features/members/widgets/full_screen_markdown_editor_sheet.dart',
    mustContain: [
      'entityMentionsEnabled',
      'EntityMentionEditingController',
      'EntityMentionTextField',
    ],
  ),
  (
    path: 'lib/features/boards/views/post_detail_screen.dart',
    mustContain: [
      'MemberBoardPostPermissions',
      'perms?.canView',
      'profileMentionActiveFrontersProvider',
      'canActiveFrontViewBoardPost',
    ],
  ),
  (
    path: 'lib/core/router/app_router.dart',
    mustContain: ['mentionViewer', 'speakingAsProvider.overrideWithBuild'],
  ),
  (
    path: 'lib/shared/widgets/profile_entity_mention_navigation.dart',
    mustContain: [
      '_freshResolutionForNavigation',
      'getMentionNoteById',
      'getPostById',
      'getMentionConversationById',
      'chatConversationAs',
    ],
  ),
  (
    path: 'lib/shared/widgets/markdown_text.dart',
    mustContain: ['builders', 'inlineSyntaxes', 'extensionSet'],
  ),
];

void main() {
  final failures = <String>[];
  for (final check in checks) {
    final file = File(check.path);
    if (!file.existsSync()) {
      failures.add('${check.path}: file does not exist');
      continue;
    }

    final source = file.readAsStringSync();
    for (final needle in check.mustContain) {
      if (!source.contains(needle)) {
        failures.add('${check.path}: missing "$needle"');
      }
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('Entity mention consumer audit failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Entity mention consumer audit passed.');
}
