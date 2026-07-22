import 'dart:convert';
import 'dart:io';
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

  group('validateAndNormalize — throw cases', () {
    FieldTemplate _makeTemplate(List<FieldTemplateEntry> entries) =>
        FieldTemplate(version: 1, entries: entries);

    test('> kMaxTemplateEntries → invalid', () {
      final entries = List.generate(
        kMaxTemplateEntries + 1,
        (i) => FieldTemplateEntry(name: 'F$i', fieldTypeId: 'text'),
      );
      expect(
        () => codec.validateAndNormalize(_makeTemplate(entries)),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.invalid,
          ),
        ),
      );
    });

    test('exactly kMaxTemplateEntries passes', () {
      final entries = List.generate(
        kMaxTemplateEntries,
        (i) => FieldTemplateEntry(name: 'F$i', fieldTypeId: 'text'),
      );
      final result = codec.validateAndNormalize(_makeTemplate(entries));
      expect(result.entries.length, kMaxTemplateEntries);
    });

    test('name > kMaxFieldNameChars → invalid', () {
      final longName = 'A' * (kMaxFieldNameChars + 1);
      expect(
        () => codec.validateAndNormalize(
          _makeTemplate([FieldTemplateEntry(name: longName, fieldTypeId: 'text')]),
        ),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.invalid,
          ),
        ),
      );
    });

    test('> kMaxChoiceOptions in choice field → invalid', () {
      final options = List.generate(
        kMaxChoiceOptions + 1,
        (i) => {'label': 'Opt $i'},
      );
      final entry = FieldTemplateEntry(
        name: 'Choice',
        fieldTypeId: 'choice',
        compactConfig: {
          'runtimeType': 'choice',
          'options': options,
          'allowsMultiple': false,
          'allowsOther': false,
        },
      );
      expect(
        () => codec.validateAndNormalize(_makeTemplate([entry])),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.invalid,
          ),
        ),
      );
    });

    test('exactly kMaxChoiceOptions passes', () {
      final options = List.generate(
        kMaxChoiceOptions,
        (i) => {'label': 'Opt $i'},
      );
      final entry = FieldTemplateEntry(
        name: 'Choice',
        fieldTypeId: 'choice',
        compactConfig: {
          'runtimeType': 'choice',
          'options': options,
          'allowsMultiple': false,
          'allowsOther': false,
        },
      );
      // Should not throw.
      final result = codec.validateAndNormalize(_makeTemplate([entry]));
      expect(result.entries.length, 1);
    });

    test('depth-2: entry is both parent and child → invalid', () {
      // Entry 0 is a group, entry 1 is a group child that is ALSO a parent of entry 2.
      final entries = [
        const FieldTemplateEntry(name: 'Root', fieldTypeId: 'group'),
        // Entry 1 is child of entry 0 AND parent of entry 2 → depth 2 → invalid.
        const FieldTemplateEntry(name: 'Mid', fieldTypeId: 'group', parentIndex: 0),
        const FieldTemplateEntry(name: 'Leaf', fieldTypeId: 'text', parentIndex: 1),
      ];
      expect(
        () => codec.validateAndNormalize(_makeTemplate(entries)),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.invalid,
          ),
        ),
      );
    });

    test('invalid colorHex (no hash) → invalid', () {
      final entry = FieldTemplateEntry(
        name: 'Choice',
        fieldTypeId: 'choice',
        compactConfig: {
          'runtimeType': 'choice',
          'options': [
            {'label': 'Red', 'colorHex': 'ff0000'}, // missing #
          ],
          'allowsMultiple': false,
          'allowsOther': false,
        },
      );
      expect(
        () => codec.validateAndNormalize(_makeTemplate([entry])),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.invalid,
          ),
        ),
      );
    });

    test('invalid colorHex (too short) → invalid', () {
      final entry = FieldTemplateEntry(
        name: 'Choice',
        fieldTypeId: 'choice',
        compactConfig: {
          'runtimeType': 'choice',
          'options': [
            {'label': 'Red', 'colorHex': '#fff'}, // 3-digit shorthand
          ],
          'allowsMultiple': false,
          'allowsOther': false,
        },
      );
      expect(
        () => codec.validateAndNormalize(_makeTemplate([entry])),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.invalid,
          ),
        ),
      );
    });

    test('valid colorHex passes', () {
      final entry = FieldTemplateEntry(
        name: 'Choice',
        fieldTypeId: 'choice',
        compactConfig: {
          'runtimeType': 'choice',
          'options': [
            {'label': 'Red', 'colorHex': '#FF0000'},
            {'label': 'Blue', 'colorHex': '#0000ff'},
          ],
          'allowsMultiple': false,
          'allowsOther': false,
        },
      );
      final result = codec.validateAndNormalize(_makeTemplate([entry]));
      expect(result.entries.length, 1);
    });
  });

  group('validateAndNormalize — normalize (no throw) cases', () {
    FieldTemplate _makeTemplate(List<FieldTemplateEntry> entries) =>
        FieldTemplate(version: 1, entries: entries);

    test('out-of-range parentIndex → promoted to top-level', () {
      final entries = [
        const FieldTemplateEntry(
          name: 'Orphan',
          fieldTypeId: 'text',
          parentIndex: 99, // out of range
        ),
      ];
      final result = codec.validateAndNormalize(_makeTemplate(entries));
      expect(result.entries[0].parentIndex, isNull);
    });

    test('negative parentIndex → promoted to top-level', () {
      final entries = [
        const FieldTemplateEntry(
          name: 'Orphan',
          fieldTypeId: 'text',
          parentIndex: -1,
        ),
      ];
      final result = codec.validateAndNormalize(_makeTemplate(entries));
      expect(result.entries[0].parentIndex, isNull);
    });

    test('parentIndex pointing at non-group entry → promoted', () {
      final entries = [
        const FieldTemplateEntry(name: 'Text', fieldTypeId: 'text'),
        // Tries to parent under a 'text' field (not a group) → promoted.
        const FieldTemplateEntry(name: 'Child', fieldTypeId: 'text', parentIndex: 0),
      ];
      final result = codec.validateAndNormalize(_makeTemplate(entries));
      expect(result.entries[1].parentIndex, isNull);
      // Entry 0 untouched.
      expect(result.entries[0].parentIndex, isNull);
    });

    test('unknown fieldTypeId entry is tolerated', () {
      const rawJson = '{"runtimeType":"mysteryType","fancyKey":42}';
      final entries = [
        const FieldTemplateEntry(
          name: 'Future Field',
          fieldTypeId: 'mysteryType',
          rawConfigJson: rawJson,
        ),
      ];
      // Should not throw.
      final result = codec.validateAndNormalize(_makeTemplate(entries));
      expect(result.entries.length, 1);
      expect(result.entries[0].fieldTypeId, 'mysteryType');
    });

    test('valid group parent is preserved', () {
      final entries = [
        const FieldTemplateEntry(name: 'MyGroup', fieldTypeId: 'group'),
        const FieldTemplateEntry(name: 'Child', fieldTypeId: 'text', parentIndex: 0),
      ];
      final result = codec.validateAndNormalize(_makeTemplate(entries));
      expect(result.entries[1].parentIndex, 0); // not promoted
    });
  });

  // ── Fix 1: streaming gzip-bomb guard ────────────────────────────────────────

  group('Fix1: streaming gzip-bomb guard', () {
    // Build a valid PF1 code whose decompressed output exceeds kMaxTemplateJsonBytes
    // without the streaming cap ever materialising the full buffer.
    String _buildBombCode() {
      // Craft a huge JSON string that will compress well, so the compressed form
      // stays under kMaxTemplateCodeChars but the decompressed form is > 256 KB.
      final bigJson = jsonEncode({
        'v': 1,
        'f': [
          // One entry with a giant name that compresses to ~nothing but inflates big.
          {'n': 'A' * (kMaxTemplateJsonBytes + 1024), 't': 'text'},
        ],
      });
      final bytes = utf8.encode(bigJson);
      final compressed = GZipCodec().encode(bytes);
      final b64 = base64Url.encode(compressed).replaceAll('=', '');
      return 'PF1:$b64';
    }

    test('oversized decompressed payload → corrupt (streaming check)', () {
      final code = _buildBombCode();
      // The pre-compress check must pass (code is not oversized).
      expect(code.length, lessThanOrEqualTo(kMaxTemplateCodeChars));

      expect(
        () => codec.decode(code),
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

  // ── Fix 2: rawConfigJson bypass for known types ──────────────────────────────

  group('Fix2: rawConfigJson bypass for known types', () {
    FieldTemplate _makeTemplate(List<FieldTemplateEntry> entries) =>
        FieldTemplate(version: 1, entries: entries);

    test('known type (choice) with rawConfigJson → invalid', () {
      const rawJson = '{"runtimeType":"choice","options":[]}';
      final entry = FieldTemplateEntry(
        name: 'Choice',
        fieldTypeId: 'choice',
        rawConfigJson: rawJson,
      );
      expect(
        () => codec.validateAndNormalize(_makeTemplate([entry])),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.invalid,
          ),
        ),
      );
    });

    test('entry with both compactConfig and rawConfigJson → invalid', () {
      final entry = FieldTemplateEntry(
        name: 'Choice',
        fieldTypeId: 'choice',
        compactConfig: const {
          'runtimeType': 'choice',
          'options': <dynamic>[],
          'allowsMultiple': false,
          'allowsOther': false,
        },
        rawConfigJson: '{"extra":"sneaky"}',
      );
      expect(
        () => codec.validateAndNormalize(_makeTemplate([entry])),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.invalid,
          ),
        ),
      );
    });

    test('unknown type with only rawConfigJson → tolerated', () {
      const rawJson = '{"runtimeType":"futureThing","x":1}';
      final entry = FieldTemplateEntry(
        name: 'Future',
        fieldTypeId: 'futureThing',
        rawConfigJson: rawJson,
      );
      // Should not throw.
      final result = codec.validateAndNormalize(_makeTemplate([entry]));
      expect(result.entries.length, 1);
    });
  });

  // ── Fix 3: malformed options caught in validateAndNormalize ─────────────────

  group('Fix3: malformed option structure → invalid', () {
    FieldTemplate _makeTemplate(List<FieldTemplateEntry> entries) =>
        FieldTemplate(version: 1, entries: entries);

    FieldTemplateEntry _choiceEntry(List<dynamic> options) => FieldTemplateEntry(
      name: 'Choice',
      fieldTypeId: 'choice',
      compactConfig: {
        'runtimeType': 'choice',
        'options': options,
        'allowsMultiple': false,
        'allowsOther': false,
      },
    );

    test('option is not a Map (int in list) → invalid', () {
      expect(
        () => codec.validateAndNormalize(_makeTemplate([_choiceEntry([123])])),
        throwsA(isA<FieldTemplateCodecException>().having(
          (e) => e.kind, 'kind', FieldTemplateCodecError.invalid,
        )),
      );
    });

    test('option label is non-String → invalid', () {
      expect(
        () => codec.validateAndNormalize(
          _makeTemplate([_choiceEntry([{'label': 5}])]),
        ),
        throwsA(isA<FieldTemplateCodecException>().having(
          (e) => e.kind, 'kind', FieldTemplateCodecError.invalid,
        )),
      );
    });

    test('option colorHex is non-String → invalid', () {
      expect(
        () => codec.validateAndNormalize(
          _makeTemplate([_choiceEntry([{'label': 'x', 'colorHex': 7}])]),
        ),
        throwsA(isA<FieldTemplateCodecException>().having(
          (e) => e.kind, 'kind', FieldTemplateCodecError.invalid,
        )),
      );
    });

    test('option missing label field → invalid', () {
      expect(
        () => codec.validateAndNormalize(
          _makeTemplate([_choiceEntry([<String, dynamic>{}])]),
        ),
        throwsA(isA<FieldTemplateCodecException>().having(
          (e) => e.kind, 'kind', FieldTemplateCodecError.invalid,
        )),
      );
    });

    test('well-formed option passes', () {
      final result = codec.validateAndNormalize(_makeTemplate([
        _choiceEntry([
          {'label': 'Red', 'colorHex': '#ff0000'},
          {'label': 'Blue'},
        ]),
      ]));
      expect(result.entries.length, 1);
    });
  });

  // ── Fix 5: validateAndNormalize version check ────────────────────────────────

  group('Fix5: validateAndNormalize version check', () {
    test('version 2 template → unsupportedVersion', () {
      final t = FieldTemplate(
        version: 2,
        entries: const [FieldTemplateEntry(name: 'X', fieldTypeId: 'text')],
      );
      expect(
        () => codec.validateAndNormalize(t),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.unsupportedVersion,
          ),
        ),
      );
    });

    test('version 0 template → unsupportedVersion', () {
      final t = FieldTemplate(
        version: 0,
        entries: const [FieldTemplateEntry(name: 'X', fieldTypeId: 'text')],
      );
      expect(
        () => codec.validateAndNormalize(t),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.unsupportedVersion,
          ),
        ),
      );
    });

    test('version 1 template → passes', () {
      final t = FieldTemplate(
        version: 1,
        entries: const [FieldTemplateEntry(name: 'X', fieldTypeId: 'text')],
      );
      // Should not throw.
      final result = codec.validateAndNormalize(t);
      expect(result.entries.length, 1);
    });

    test('fieldTypeId over the length cap → invalid', () {
      final t = FieldTemplate(
        version: 1,
        entries: [
          FieldTemplateEntry(
            name: 'X',
            fieldTypeId: 'a' * (kMaxFieldTypeIdChars + 1),
          ),
        ],
      );
      expect(
        () => codec.validateAndNormalize(t),
        throwsA(
          isA<FieldTemplateCodecException>().having(
            (e) => e.kind,
            'kind',
            FieldTemplateCodecError.invalid,
          ),
        ),
      );
    });

    test('strips bidi/zero-width impersonation chars from names', () {
      // U+202E (right-to-left override) + U+200B (zero-width space) in a name.
      final dirty =
          'A${String.fromCharCode(0x202E)}B${String.fromCharCode(0x200B)}C';
      final t = FieldTemplate(
        version: 1,
        entries: [FieldTemplateEntry(name: dirty, fieldTypeId: 'text')],
      );
      final result = codec.validateAndNormalize(t);
      expect(result.entries.single.name, 'ABC');
    });

    test('leaves a clean template untouched (no needless realloc)', () {
      final t = FieldTemplate(
        version: 1,
        entries: const [FieldTemplateEntry(name: 'Bio', fieldTypeId: 'text')],
      );
      expect(identical(codec.validateAndNormalize(t), t), isTrue);
    });
  });
}
