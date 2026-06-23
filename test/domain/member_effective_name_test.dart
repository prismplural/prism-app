import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';

Member _member({
  required String name,
  String? displayName,
  String? pluralkitDisplayName,
}) => Member(
  id: 'm1',
  name: name,
  displayName: displayName,
  pluralkitDisplayName: pluralkitDisplayName,
  createdAt: DateTime(2026),
);

void main() {
  group('Member.effectiveName', () {
    test('preferDisplayName=false always returns name', () {
      final m = _member(
        name: 'Alex',
        displayName: 'Alexandra',
        pluralkitDisplayName: 'Lexi',
      );
      expect(m.effectiveName(preferDisplayName: false), 'Alex');
    });

    test('display picks displayName when present', () {
      final m = _member(
        name: 'Alex',
        displayName: 'Alexandra',
        pluralkitDisplayName: 'Lexi',
      );
      expect(m.effectiveName(preferDisplayName: true), 'Alexandra');
    });

    test('falls to pluralkitDisplayName when displayName is null', () {
      final m = _member(
        name: 'Alex',
        displayName: null,
        pluralkitDisplayName: 'Lexi',
      );
      expect(m.effectiveName(preferDisplayName: true), 'Lexi');
    });

    test('falls to pluralkitDisplayName when displayName is blank', () {
      final m = _member(
        name: 'Alex',
        displayName: '   ',
        pluralkitDisplayName: 'Lexi',
      );
      expect(m.effectiveName(preferDisplayName: true), 'Lexi');
    });

    test('falls to name when both display fields are null', () {
      final m = _member(name: 'Alex');
      expect(m.effectiveName(preferDisplayName: true), 'Alex');
    });

    test('falls to name when both display fields are blank', () {
      final m = _member(
        name: 'Alex',
        displayName: '  ',
        pluralkitDisplayName: '\t',
      );
      expect(m.effectiveName(preferDisplayName: true), 'Alex');
    });

    test('all-whitespace display fields are treated as absent', () {
      final m = _member(
        name: 'Alex',
        displayName: '\n ',
        pluralkitDisplayName: '   ',
      );
      expect(m.effectiveName(preferDisplayName: true), 'Alex');
      expect(m.effectiveName(preferDisplayName: false), 'Alex');
    });
  });
}
