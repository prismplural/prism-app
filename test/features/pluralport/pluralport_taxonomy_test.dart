import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_exporter.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';

Json fixture() => {
  'pluralport_version': '0.1',
  'producer': {'app': 'Foreign', 'app_id': 'foreign'},
  'systems': [
    {'id': 'system', 'name': 'System'},
  ],
  'members': [
    {'id': 'member', 'system_id': 'system', 'name': 'Member'},
  ],
  'notes': [
    {
      'id': 'note',
      'system_id': 'system',
      'member_id': 'member',
      'title': 'Note',
      'body': 'Body',
    },
  ],
  'assets': [
    {'id': 'asset', 'kind': 'image', 'uri': 'https://example.invalid/image'},
  ],
  'front_periods': [
    {
      'id': 'period',
      'system_id': 'system',
      'started_at': '2026-01-01T00:00:00Z',
      'assignments': [
        {'member_id': 'member', 'front_role': 'member'},
      ],
    },
  ],
  'taxonomy_terms': [
    {
      'id': 'root',
      'system_id': 'system',
      'kind': 'tag',
      'name': 'Root',
      'source_refs': [
        {'app': 'foreign', 'collection': 'tags', 'id': 'root-tag'},
      ],
      'extensions': {
        'foreign': {'unknown_term_field': 'retain'},
      },
    },
    {
      'id': 'child',
      'system_id': 'system',
      'kind': 'tag',
      'name': 'Child',
      'parent_term_id': 'root',
    },
  ],
  'taxonomy_assignments': [
    {
      'id': 'member-assignment',
      'term_id': 'child',
      'subject_type': 'member',
      'subject_id': 'member',
    },
    {
      'id': 'note-assignment',
      'term_id': 'root',
      'subject_type': 'note',
      'subject_id': 'note',
    },
    {
      'id': 'asset-assignment',
      'term_id': 'child',
      'subject_type': 'asset',
      'subject_id': 'asset',
    },
    {
      'id': 'period-assignment',
      'term_id': 'root',
      'subject_type': 'front_period',
      'subject_id': 'period',
    },
    {
      'id': 'custom-assignment',
      'term_id': 'child',
      'subject_type': 'custom',
      'subject_id': 'foreign:opaque-subject',
      'unknown_assignment_field': {'subject_id': 'must-stay-opaque'},
    },
  ],
};

PluralPortBundle exportNoEdits(PluralPortImportPlan plan) {
  final systemId =
      PluralPortMapper.rows(
            plan.archive['envelope'] as Json,
            'systems',
          ).single['id']
          as String;
  return PluralPortExporter(plan.native, systemId).build([plan.archive]);
}

Map<String, Json> byId(Json envelope, String path) => {
  for (final row in PluralPortMapper.rows(envelope, path))
    row['id'] as String: row,
};

Json assignmentFor(Json envelope, String subjectType) => PluralPortMapper.rows(
  envelope,
  'taxonomy_assignments',
).singleWhere((assignment) => assignment['subject_type'] == subjectType);

void main() {
  test('taxonomy identity and graph survive two no-edit round trips', () {
    final firstPlan = PluralPortMapper.plan(PluralPortBundle(fixture()));
    final first = exportNoEdits(firstPlan);
    final secondPlan = PluralPortMapper.plan(first);
    final second = exportNoEdits(secondPlan);

    final firstTerms = byId(first.envelope, 'taxonomy_terms');
    final secondTerms = byId(second.envelope, 'taxonomy_terms');
    final firstRoot = firstTerms.values.singleWhere(
      (term) => term['name'] == 'Root',
    );
    final firstChild = firstTerms.values.singleWhere(
      (term) => term['name'] == 'Child',
    );
    final secondRoot = secondTerms.values.singleWhere(
      (term) => term['name'] == 'Root',
    );
    final secondChild = secondTerms.values.singleWhere(
      (term) => term['name'] == 'Child',
    );

    expect(firstRoot['id'], isNot('root'));
    expect(firstChild['parent_term_id'], firstRoot['id']);
    expect(secondRoot['id'], firstRoot['id']);
    expect(secondChild['id'], firstChild['id']);
    expect(secondChild['parent_term_id'], secondRoot['id']);
    expect((secondRoot['extensions'] as Map)['foreign'], {
      'unknown_term_field': 'retain',
    });
    expect(
      (secondRoot['source_refs'] as List).any(
        (ref) =>
            ref is Map &&
            ref['app'] == 'foreign' &&
            ref['collection'] == 'tags' &&
            ref['id'] == 'root-tag',
      ),
      isTrue,
    );

    final secondAssignments = byId(second.envelope, 'taxonomy_assignments');
    final firstMembers = byId(first.envelope, 'members');
    final firstNotes = byId(first.envelope, 'notes');
    final firstAssets = byId(first.envelope, 'assets');
    final firstPeriods = byId(first.envelope, 'front_periods');
    final memberAssignment = assignmentFor(first.envelope, 'member');
    final noteAssignment = assignmentFor(first.envelope, 'note');
    final assetAssignment = assignmentFor(first.envelope, 'asset');
    final periodAssignment = assignmentFor(first.envelope, 'front_period');
    final customAssignment = assignmentFor(first.envelope, 'custom');
    expect(memberAssignment['term_id'], firstChild['id']);
    expect(memberAssignment['subject_id'], firstMembers.keys.single);
    expect(noteAssignment['subject_id'], firstNotes.keys.single);
    expect(assetAssignment['subject_id'], firstAssets.keys.single);
    expect(periodAssignment['subject_id'], firstPeriods.keys.single);
    expect(customAssignment['subject_id'], 'foreign:opaque-subject');
    expect(
      (customAssignment['unknown_assignment_field'] as Map)['subject_id'],
      'must-stay-opaque',
    );
    for (final assignment in secondAssignments.values) {
      expect(secondTerms, contains(assignment['term_id']));
    }
  });

  test('empty taxonomy modules import and export', () {
    final source = fixture()
      ..['taxonomy_terms'] = []
      ..['taxonomy_assignments'] = [];
    final output = exportNoEdits(
      PluralPortMapper.plan(PluralPortBundle(source)),
    );

    expect(PluralPortMapper.rows(output.envelope, 'taxonomy_terms'), isEmpty);
    expect(
      PluralPortMapper.rows(output.envelope, 'taxonomy_assignments'),
      isEmpty,
    );
    expect(() => PluralPortMapper.plan(output), returnsNormally);
  });

  test('rejects taxonomy assignments without a valid term reference', () {
    for (final termId in ['missing', null]) {
      final source = PluralPortMapper.clone(fixture());
      (source['taxonomy_assignments'] as List).first['term_id'] = termId;

      expect(
        () => PluralPortMapper.plan(PluralPortBundle(source)),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('rejects cycles in the taxonomy term hierarchy', () {
    final source = fixture();
    (source['taxonomy_terms'] as List).first['parent_term_id'] = 'child';

    expect(
      () => PluralPortMapper.plan(PluralPortBundle(source)),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Cycle in taxonomy_terms hierarchy.'),
        ),
      ),
    );
  });
}
