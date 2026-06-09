import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/member_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';

void main() {
  group('memberFieldDefinition metadata', () {
    test('id is "member"', () {
      expect(memberFieldDefinition.id, 'member');
    });

    test('legacyIntValue is null for registry-only type', () {
      expect(memberFieldDefinition.legacyIntValue, isNull);
    });

    test('label key is customFieldTypeMember', () {
      expect(memberFieldDefinition.labelL10nKey, 'customFieldTypeMember');
    });

    test('is registered globally', () {
      expect(
        customFieldTypeRegistry.lookupById('member'),
        same(memberFieldDefinition),
      );
    });
  });

  group('memberFieldDefinition.valueParser', () {
    test('null and empty string parse to empty MemberFieldValue', () {
      expect(memberFieldDefinition.valueParser(null), const MemberFieldValue());
      expect(memberFieldDefinition.valueParser(''), const MemberFieldValue());
    });

    test('parses memberIds and dedupes values', () {
      expect(
        memberFieldDefinition.valueParser(
          '{"memberIds":["member-b","member-a","member-b"]}',
        ),
        const MemberFieldValue(memberIds: {'member-a', 'member-b'}),
      );
    });

    test('ignores non-string memberIds without throwing', () {
      expect(
        memberFieldDefinition.valueParser(
          '{"memberIds":["member-a",42,null,{"id":"member-b"}]}',
        ),
        const MemberFieldValue(memberIds: {'member-a'}),
      );
    });

    test('preserves unknown top-level keys for forward compatibility', () {
      expect(
        memberFieldDefinition.valueParser(
          '{"memberIds":["member-a"],"relationshipMeta":{"kind":"sibling"},"futureFlag":true}',
        ),
        const MemberFieldValue(
          memberIds: {'member-a'},
          extra: {
            'relationshipMeta': {'kind': 'sibling'},
            'futureFlag': true,
          },
        ),
      );
    });

    test('malformed JSON and wrong shapes parse to empty MemberFieldValue', () {
      for (final raw in <String>[
        'not json',
        '[]',
        '{"memberIds":"member-a"}',
        '{"memberIds":{}}',
        '{"other":["member-a"]}',
      ]) {
        expect(
          memberFieldDefinition.valueParser(raw),
          const MemberFieldValue(),
          reason: raw,
        );
      }
    });
  });

  group('memberFieldDefinition.valueEncoder', () {
    test('empty member set encodes to empty string', () {
      expect(memberFieldDefinition.valueEncoder(const MemberFieldValue()), '');
    });

    test('member IDs encode as deterministic sorted JSON', () {
      expect(
        memberFieldDefinition.valueEncoder(
          const MemberFieldValue(
            memberIds: {'member-c', 'member-a', 'member-b'},
          ),
        ),
        '{"memberIds":["member-a","member-b","member-c"]}',
      );
    });

    test('unknown top-level keys re-emit deterministically', () {
      expect(
        memberFieldDefinition.valueEncoder(
          const MemberFieldValue(
            memberIds: {'member-b', 'member-a'},
            extra: {
              'relationshipMeta': {'kind': 'sibling'},
              'futureFlag': true,
            },
          ),
        ),
        '{"memberIds":["member-a","member-b"],"futureFlag":true,"relationshipMeta":{"kind":"sibling"}}',
      );
    });

    test('extra payload keeps an empty member selection encodable', () {
      expect(
        memberFieldDefinition.valueEncoder(
          const MemberFieldValue(extra: {'futureFlag': true}),
        ),
        '{"memberIds":[],"futureFlag":true}',
      );
    });

    test('wrong typed value variant encodes to empty string', () {
      expect(
        memberFieldDefinition.valueEncoder(const TextFieldValue('member-a')),
        '',
      );
    });
  });
}
