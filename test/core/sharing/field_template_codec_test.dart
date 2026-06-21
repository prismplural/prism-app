import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sharing/field_template_codec.dart';
import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';

// Build a small template directly (bypasses domain fields) to test raw codec.
FieldTemplate _smallTemplate() {
  return FieldTemplate(
    version: 1,
    entries: [
      const FieldTemplateEntry(
        name: 'Group',
        fieldTypeId: 'group',
        compactConfig: {'runtimeType': 'group', 'icon': '🌟'},
      ),
      const FieldTemplateEntry(
        name: 'Mood',
        fieldTypeId: 'choice',
        parentIndex: 0,
        compactConfig: {
          'runtimeType': 'choice',
          'options': [
            {'label': 'Happy', 'colorHex': '#ff0000'},
            {'label': 'Sad', 'colorHex': '#0000ff'},
          ],
          'allowsMultiple': false,
          'allowsOther': false,
        },
      ),
    ],
  );
}

FieldTemplate _templateFromDomain() {
  final now = DateTime.now();
  final group = CustomField(
    id: 'g1',
    name: 'Group',
    fieldType: CustomFieldType.text,
    createdAt: now,
    fieldTypeId: 'group',
    typeConfig: const GroupConfig(icon: '🌟'),
  );
  final choice = CustomField(
    id: 'c1',
    name: 'Mood',
    fieldType: CustomFieldType.choice,
    createdAt: now,
    fieldTypeId: 'choice',
    parentFieldId: 'g1',
    typeConfig: const ChoiceConfig(
      options: [
        ChoiceOption(id: 'o1', label: 'Happy', colorHex: '#ff0000', sortOrder: 0),
        ChoiceOption(id: 'o2', label: 'Sad', colorHex: '#0000ff', sortOrder: 1),
      ],
    ),
  );
  return FieldTemplate.fromDomain([group, choice]);
}

void main() {
  final codec = FieldTemplateCodec();

  group('PF1 codec basic', () {
    test('round-trip equality (small template)', () {
      final t = _smallTemplate();
      final code = codec.encode(t);
      final decoded = codec.decode(code);

      expect(decoded.version, t.version);
      expect(decoded.entries.length, t.entries.length);
      expect(decoded.entries[0].name, t.entries[0].name);
      expect(decoded.entries[0].fieldTypeId, t.entries[0].fieldTypeId);
      expect(decoded.entries[1].name, t.entries[1].name);
      expect(decoded.entries[1].parentIndex, t.entries[1].parentIndex);
    });

    test('encoded string starts with PF1:', () {
      final code = codec.encode(_smallTemplate());
      expect(code.startsWith('PF1:'), isTrue);
    });

    test('no trailing = padding in the base64url portion', () {
      final code = codec.encode(_smallTemplate());
      final payload = code.substring('PF1:'.length);
      expect(payload.endsWith('='), isFalse);
    });

    test('round-trip via domain fromDomain path', () {
      final t = _templateFromDomain();
      final code = codec.encode(t);
      final decoded = codec.decode(code);

      expect(decoded.entries.length, 2);
      expect(decoded.entries[0].name, 'Group');
      expect(decoded.entries[1].name, 'Mood');
      expect(decoded.entries[1].parentIndex, 0);
    });
  });

  group('PF1 error cases', () {
    test('flipping one char in payload → corrupt', () {
      final code = codec.encode(_smallTemplate());
      // Flip a character in the middle of the payload.
      final payload = code.substring('PF1:'.length);
      final mid = payload.length ~/ 2;
      final flipped = payload.substring(0, mid) +
          (payload[mid] == 'A' ? 'B' : 'A') +
          payload.substring(mid + 1);
      final tampered = 'PF1:$flipped';

      expect(
        () => codec.decode(tampered),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.corrupt,
          ),
        ),
      );
    });

    test('wrong version prefix PF9: → unsupportedVersion', () {
      final code = codec.encode(_smallTemplate());
      final withWrongVersion = 'PF9:${code.substring('PF1:'.length)}';

      expect(
        () => codec.decode(withWrongVersion),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.unsupportedVersion,
          ),
        ),
      );
    });

    test('missing PF prefix entirely → unsupportedVersion', () {
      expect(
        () => codec.decode('notacode'),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.unsupportedVersion,
          ),
        ),
      );
    });

    test('truncated payload → corrupt', () {
      final code = codec.encode(_smallTemplate());
      final truncated = code.substring(0, code.length - 5);

      expect(
        () => codec.decode(truncated),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            // Could be unsupportedVersion (if prefix is wrong) or corrupt.
            anyOf(
              FieldTemplateCodecError.corrupt,
              FieldTemplateCodecError.unsupportedVersion,
            ),
          ),
        ),
      );
    });

    test('truncated payload that keeps prefix → corrupt', () {
      final code = codec.encode(_smallTemplate());
      // Keep prefix but truncate body enough to break gzip.
      final truncated = 'PF1:${code.substring('PF1:'.length, 'PF1:'.length + 4)}';

      expect(
        () => codec.decode(truncated),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.corrupt,
          ),
        ),
      );
    });
  });

  group('PF1 large template', () {
    test('50-field template (max) round-trips', () {
      final entries = List.generate(50, (i) {
        return FieldTemplateEntry(
          name: 'Field $i',
          fieldTypeId: i % 2 == 0 ? 'text' : 'scale',
          compactConfig: i % 2 == 0
              ? null
              : {'runtimeType': 'scale', 'emoji': '⭐', 'steps': 5},
        );
      });
      final t = FieldTemplate(version: 1, entries: entries);

      final code = codec.encode(t);
      final decoded = codec.decode(code);

      expect(decoded.entries.length, 50);
      expect(decoded.entries[0].name, 'Field 0');
      expect(decoded.entries[49].name, 'Field 49');
      expect(decoded.entries[1].fieldTypeId, 'scale');
    });
  });
}
