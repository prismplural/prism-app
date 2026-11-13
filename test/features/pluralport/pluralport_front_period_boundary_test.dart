import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_exporter.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';

const _systemId = 'system-1';
const _memberId = 'member-1';
const _memberName = 'Fronter';

/// A minimal native export document: one member and whatever front sessions a
/// test needs. Native storage is never written by these tests; the map is the
/// same shape `DataExportService.buildExport().toJson()` produces.
Json nativeWith(Map<String, dynamic> frontSession) => {
  'formatVersion': '1.0',
  'systemSettings': [
    {'systemName': 'Test system'},
  ],
  'headmates': [
    {'id': _memberId, 'name': _memberName, 'createdAt': '2026-01-01T00:00:00Z'},
  ],
  'frontSessions': [frontSession],
};

Json session({
  required String id,
  required String startTime,
  String? endTime,
}) => {
  'id': id,
  'startTime': startTime,
  'endTime': endTime,
  'headmateId': _memberId,
  'sessionType': 0,
  'isHealthKitImport': false,
};

PluralPortBundle exported(Json native) =>
    PluralPortExporter(native, _systemId).build(const []);

List<Map<String, dynamic>> warningsWithCode(Json envelope, String code) =>
    (envelope['warnings'] as List)
        .cast<Map<String, dynamic>>()
        .where((warning) => warning['code'] == code)
        .toList();

void main() {
  test(
    'an inverted native front period exports as the shortest valid interval, '
    'warns by record id, and keeps the original row',
    () {
      final bundle = exported(
        nativeWith(
          session(
            id: 'period-inverted',
            startTime: '2026-01-02T02:10:00.000Z',
            endTime: '2026-01-02T02:00:00.000Z',
          ),
        ),
      );
      final periods = PluralPortMapper.rows(bundle.envelope, 'front_periods');
      expect(periods, hasLength(1));
      final period = periods.single;

      // The portable interval is clamped to started_at + 1s, not dropped and
      // not copied through (which would produce a file Prism refuses to read).
      expect(period['started_at'], '2026-01-02T02:10:00.000Z');
      expect(period['ended_at'], '2026-01-02T02:10:01.000Z');
      expect(
        DateTime.parse(
          period['ended_at'] as String,
        ).isAfter(DateTime.parse(period['started_at'] as String)),
        isTrue,
      );

      // The untouched native row stays available for traceability.
      final prism = ((period['extensions'] as Map)['prism'] as Map)
          .cast<String, dynamic>();
      final original = (prism['native'] as Map).cast<String, dynamic>();
      expect(original['id'], 'period-inverted');
      expect(original['startTime'], '2026-01-02T02:10:00.000Z');
      expect(original['endTime'], '2026-01-02T02:00:00.000Z');
      expect(original['headmateId'], _memberId);
      expect(prism['original_front_period_boundaries'], {
        'started_at': '2026-01-02T02:10:00.000Z',
        'ended_at': '2026-01-02T02:00:00.000Z',
      });

      final warnings = warningsWithCode(
        bundle.envelope,
        'front_period_adjusted',
      );
      expect(warnings, hasLength(1));
      final message = warnings.single['message'] as String;
      expect(warnings.single['level'], 'warning');
      expect(message, contains('period-inverted'));
      expect(message, contains('one second after started_at'));
      // No personal content: no member id, name, or timestamp detail.
      expect(message, isNot(contains(_memberName)));
      expect(message, isNot(contains(_memberId)));
      expect(message, isNot(contains('2026-01-02')));
    },
  );

  test('valid and zero-length front periods are exported unchanged', () {
    final bundle = exported(
      nativeWith(
        session(
          id: 'period-valid',
          startTime: '2026-01-01T00:00:00.000Z',
          endTime: '2026-01-01T01:00:00.000Z',
        ),
      ),
    );
    final period = PluralPortMapper.rows(
      bundle.envelope,
      'front_periods',
    ).single;
    expect(period['started_at'], '2026-01-01T00:00:00.000Z');
    expect(period['ended_at'], '2026-01-01T01:00:00.000Z');
    expect(warningsWithCode(bundle.envelope, 'front_period_adjusted'), isEmpty);
    final original =
        (((period['extensions'] as Map)['prism'] as Map)['native'] as Map)
            .cast<String, dynamic>();
    expect(original['endTime'], '2026-01-01T01:00:00.000Z');

    // The shared contract repairs only strictly inverted intervals; an equal
    // pair is left exactly as stored (and still plans, see the mapper rule).
    final equal = PluralPortMapper.rows(
      exported(
        nativeWith(
          session(
            id: 'period-equal',
            startTime: '2026-01-01T02:00:00.000Z',
            endTime: '2026-01-01T02:00:00.000Z',
          ),
        ),
      ).envelope,
      'front_periods',
    ).single;
    expect(equal['started_at'], '2026-01-01T02:00:00.000Z');
    expect(equal['ended_at'], '2026-01-01T02:00:00.000Z');
  });

  test(
    'a repair makes the export plan cleanly, so Prism can import itself',
    () {
      final bundle = exported(
        nativeWith(
          session(
            id: 'period-inverted',
            startTime: '2026-01-02T02:10:00.000Z',
            endTime: '2026-01-02T02:00:00.000Z',
          ),
        ),
      );
      // This is the failure the phone hit: planning the export threw
      // FormatException('Front period ends before it starts') and blocked the
      // whole archive. The repaired file must plan and land the repaired end.
      final plan = PluralPortMapper.plan(
        PluralPortBundle.decode(bundle.encode()),
      );
      final sessions = PluralPortMapper.rows(plan.native, 'frontSessions');
      expect(sessions, hasLength(1));
      expect(sessions.single['startTime'], '2026-01-02T02:10:00.000Z');
      expect(sessions.single['endTime'], '2026-01-02T02:10:01.000Z');
    },
  );

  test(
    'a malformed foreign archive is still rejected and names the record',
    () {
      final foreign = <String, dynamic>{
        'pluralport_version': '0.1',
        'producer': {'app': 'Other', 'app_id': 'other'},
        'systems': [
          {'id': 'sys', 'name': 'System'},
        ],
        'members': [
          {'id': 'm', 'name': 'Member'},
        ],
        'front_periods': [
          {
            'id': 'bad-period',
            'system_id': 'sys',
            'started_at': '2026-01-01T05:00:00Z',
            'ended_at': '2026-01-01T04:00:00Z',
            'assignments': [
              {'member_id': 'm', 'front_role': 'member'},
            ],
          },
        ],
      };
      expect(
        () => PluralPortService.previewBytes(
          Uint8List.fromList(utf8.encode(jsonEncode(foreign))),
        ),
        throwsA(
          isA<FormatException>()
              .having(
                (error) => error.message,
                'message',
                contains('Front period ends before it starts'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('front_periods/bad-period'),
              ),
        ),
      );
    },
  );

  test('a foreign archive with ordered periods still plans', () {
    final foreign = <String, dynamic>{
      'pluralport_version': '0.1',
      'producer': {'app': 'Other', 'app_id': 'other'},
      'systems': [
        {'id': 'sys', 'name': 'System'},
      ],
      'members': [
        {'id': 'm', 'name': 'Member'},
      ],
      'front_periods': [
        {
          'id': 'good-period',
          'system_id': 'sys',
          'started_at': '2026-01-01T04:00:00Z',
          'ended_at': '2026-01-01T05:00:00Z',
          'assignments': [
            {'member_id': 'm', 'front_role': 'member'},
          ],
        },
      ],
    };
    final plan = PluralPortService.previewBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(foreign))),
    );
    expect(PluralPortMapper.rows(plan.native, 'frontSessions'), hasLength(1));
  });
}
