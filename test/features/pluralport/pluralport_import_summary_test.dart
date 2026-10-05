import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';

void main() {
  test('preview separates native records, retained data and missing files', () {
    final plan = PluralPortMapper.plan(
      PluralPortBundle(
        {
          'pluralport_version': '0.1',
          'producer': {'app': 'Example'},
          'systems': [
            {'id': 's', 'name': 'Example system'},
          ],
          'members': [
            {'id': 'm', 'name': 'Example member'},
          ],
          'front_events': [
            {'id': 'event', 'kind': 'custom', 'assignments': []},
          ],
          'taxonomy_terms': [
            {'id': 'tag', 'name': 'Tag'},
          ],
          'polls': {'future_version': true},
          'assets': [
            {'id': 'missing', 'kind': 'image', 'bundle_path': 'missing.png'},
            {
              'id': 'link',
              'kind': 'image',
              'uri': 'https://example.invalid/a.png',
            },
            {'id': 'binary', 'kind': 'binary', 'bundle_path': 'opaque.bin'},
          ],
          'extensions': {
            'example': {'future': true},
            'prism': {
              'native_modules': {
                'reminders': [
                  {'id': 'r', 'title': 'Reminder'},
                ],
                'systemSettings': [
                  {'accentColorHex': '#112233'},
                ],
              },
            },
          },
        },
        files: {
          'opaque.bin': Uint8List.fromList([1, 2, 3]),
        },
      ),
    );
    final summary = plan.summary;
    expect(summary.ready, {'members': 1, 'reminders': 1});
    expect(summary.retained, {
      'frontEvents': 1,
      'taxonomyTerms': 1,
      'polls': null,
      'extraData': null,
    });
    expect(summary.systemProfiles, 1);
    expect(summary.hasPreferences, isTrue);
    expect(summary.bundledFiles, 1);
    expect(summary.missingFiles, 1);
    expect(summary.unbundledMedia, 1);
  });

  test('unsupported field values stay out of usable counts', () {
    final summary = PluralPortMapper.plan(
      PluralPortBundle({
        'pluralport_version': '0.1',
        'producer': {'app': 'Example'},
        'members': [
          {'id': 'm', 'name': 'Member'},
        ],
        'custom_fields': [
          {'id': 'f', 'name': 'Future', 'value_type': 'future'},
        ],
        'custom_field_values': [
          {
            'id': 'v',
            'field_id': 'f',
            'subject_type': 'member',
            'subject_id': 'm',
            'value': 'future',
          },
        ],
      }),
    ).summary;
    expect(summary.ready, {'members': 1});
    expect(summary.retained['fields'], 1);
    expect(summary.retained['fieldValues'], 1);
    expect(summary.hasSystemProfile, isFalse);
    expect(summary.hasPreferences, isFalse);
  });
}
