import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('syncRecord mutation atomicity audit', () {
    const requiredRunSyncedWrite = <String, List<String>>{
      'lib/data/repositories/drift_custom_fields_repository.dart': [
        'createField',
        'createFieldAtEnd',
        'createFieldFromImport',
        'updateField',
        '_writePartial',
        'reorderFields',
        'deleteField',
        'deleteAllFields',
      ],
      'lib/data/repositories/drift_front_session_comments_repository.dart': [
        'reparentComments',
        'reparentCommentsAtOrAfter',
      ],
      'lib/data/repositories/drift_member_board_posts_repository.dart': [
        'markInboxOpenedFor',
      ],
      'lib/data/repositories/drift_member_repository.dart': [
        'clearPluralKitLink',
        'stampDeletePushStartedAt',
      ],
      'lib/data/repositories/drift_system_settings_repository.dart': [
        'updateTerminologyFields',
        'updateFrontingReminders',
        'updateFeatureToggles',
      ],
    };

    for (final entry in requiredRunSyncedWrite.entries) {
      test('${entry.key} has no known method-level dual-write gaps', () {
        final source = File(entry.key).readAsStringSync();
        for (final methodName in entry.value) {
          final body = _methodBody(source, methodName);
          expect(
            body,
            contains('runSyncedWrite'),
            reason:
                '$methodName writes app data and emits syncRecord*; the data '
                'write and durable outbox intent must be committed by the same '
                'runSyncedWrite transaction. This catches the method-level '
                'false negatives that a file-level grep missed.',
          );
        }
      });
    }
  });
}

String _methodBody(String source, String methodName) {
  final declaration = RegExp(
    r'(?:Future(?:<[^>]+>)?|void)\s+' + RegExp.escape(methodName) + r'\s*\(',
  ).firstMatch(source);
  if (declaration == null) {
    fail('Could not find method declaration for $methodName');
  }

  final paramsStart = source.indexOf('(', declaration.start);
  final paramsEnd = _matchingDelimiter(source, paramsStart, 0x28, 0x29);
  final bodyStart = source.indexOf('{', paramsEnd);
  if (bodyStart < 0) {
    fail('Could not find block body for $methodName');
  }

  final arrowStart = source.indexOf('=>', paramsEnd);
  if (arrowStart >= 0 && arrowStart < bodyStart) {
    fail('$methodName has an arrow body; this audit expects a block body');
  }

  final bodyEnd = _matchingDelimiter(source, bodyStart, 0x7b, 0x7d);
  return source.substring(bodyStart, bodyEnd + 1);
}

int _matchingDelimiter(
  String source,
  int start,
  int openCodeUnit,
  int closeCodeUnit,
) {
  var depth = 0;
  for (var index = start; index < source.length; index++) {
    final char = source.codeUnitAt(index);
    if (char == openCodeUnit) {
      depth++;
    } else if (char == closeCodeUnit) {
      depth--;
      if (depth == 0) {
        return index;
      }
    }
  }
  fail('Could not find matching delimiter');
}
