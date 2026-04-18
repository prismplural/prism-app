import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_member_matcher.dart';

Member _local({
  required String id,
  required String name,
  String? pluralkitUuid,
  bool ignored = false,
}) {
  return Member(
    id: id,
    name: name,
    createdAt: DateTime(2026),
    pluralkitUuid: pluralkitUuid,
    pluralkitSyncIgnored: ignored,
  );
}

PKMember _pk({
  required String id,
  required String name,
  String? uuid,
}) {
  return PKMember(
    id: id,
    uuid: uuid ?? 'uuid-$id',
    name: name,
  );
}

void main() {
  const matcher = PkMemberMatcher();

  test('exact match (unique) → confidence.exact', () {
    final locals = [_local(id: 'l1', name: 'Alice')];
    final pk = [_pk(id: 'pk1', name: 'Alice')];

    final suggestions = matcher.suggest(locals, pk);
    expect(suggestions, hasLength(1));
    expect(suggestions.first.confidence, PkMatchConfidence.exact);
    expect(suggestions.first.suggestedLocal?.id, 'l1');
  });

  test('case-insensitive match → confidence.caseInsensitive', () {
    final locals = [_local(id: 'l1', name: 'alice')];
    final pk = [_pk(id: 'pk1', name: 'Alice')];

    final suggestions = matcher.suggest(locals, pk);
    expect(suggestions.first.confidence, PkMatchConfidence.caseInsensitive);
    expect(suggestions.first.suggestedLocal?.id, 'l1');
  });

  test('whitespace-trimmed match counts as exact', () {
    final locals = [_local(id: 'l1', name: '  Alice  ')];
    final pk = [_pk(id: 'pk1', name: 'Alice')];

    final suggestions = matcher.suggest(locals, pk);
    expect(suggestions.first.confidence, PkMatchConfidence.exact);
  });

  test('multiple PK with same name → all none (ambiguous)', () {
    final locals = [_local(id: 'l1', name: 'Alice')];
    final pk = [
      _pk(id: 'pk1', name: 'Alice'),
      _pk(id: 'pk2', name: 'Alice'),
    ];

    final suggestions = matcher.suggest(locals, pk);
    expect(suggestions, hasLength(2));
    for (final s in suggestions) {
      expect(s.confidence, PkMatchConfidence.none);
      expect(s.suggestedLocal, isNull);
    }
  });

  test('multiple locals with same name → none', () {
    final locals = [
      _local(id: 'l1', name: 'Alice'),
      _local(id: 'l2', name: 'Alice'),
    ];
    final pk = [_pk(id: 'pk1', name: 'Alice')];

    final suggestions = matcher.suggest(locals, pk);
    expect(suggestions.first.confidence, PkMatchConfidence.none);
    expect(suggestions.first.suggestedLocal, isNull);
  });

  test('no match → none', () {
    final locals = [_local(id: 'l1', name: 'Alice')];
    final pk = [_pk(id: 'pk1', name: 'Bob')];

    final suggestions = matcher.suggest(locals, pk);
    expect(suggestions.first.confidence, PkMatchConfidence.none);
    expect(suggestions.first.suggestedLocal, isNull);
  });

  test('already-linked locals are excluded from candidacy', () {
    final locals = [
      _local(id: 'l1', name: 'Alice', pluralkitUuid: 'existing-uuid'),
    ];
    final pk = [_pk(id: 'pk1', name: 'Alice')];

    final suggestions = matcher.suggest(locals, pk);
    expect(suggestions.first.confidence, PkMatchConfidence.none);
    expect(suggestions.first.suggestedLocal, isNull);
  });

  test('sync-ignored locals are excluded from candidacy', () {
    final locals = [_local(id: 'l1', name: 'Alice', ignored: true)];
    final pk = [_pk(id: 'pk1', name: 'Alice')];

    final suggestions = matcher.suggest(locals, pk);
    expect(suggestions.first.confidence, PkMatchConfidence.none);
  });

  test('mixed: exact + case-insensitive + no-match + ambiguous', () {
    final locals = [
      _local(id: 'l1', name: 'Alice'),
      _local(id: 'l2', name: 'bob'),
      _local(id: 'l3', name: 'Charlie'),
    ];
    final pk = [
      _pk(id: 'pk1', name: 'Alice'),
      _pk(id: 'pk2', name: 'Bob'),
      _pk(id: 'pk3', name: 'Dave'),
      _pk(id: 'pk4', name: 'Charlie'),
      _pk(id: 'pk5', name: 'Charlie'),
    ];

    final suggestions = matcher.suggest(locals, pk);
    final byPkId = {for (final s in suggestions) s.pkMember.id: s};

    expect(byPkId['pk1']!.confidence, PkMatchConfidence.exact);
    expect(byPkId['pk1']!.suggestedLocal?.id, 'l1');

    expect(byPkId['pk2']!.confidence, PkMatchConfidence.caseInsensitive);
    expect(byPkId['pk2']!.suggestedLocal?.id, 'l2');

    expect(byPkId['pk3']!.confidence, PkMatchConfidence.none);

    // Charlie is ambiguous on PK side.
    expect(byPkId['pk4']!.confidence, PkMatchConfidence.none);
    expect(byPkId['pk5']!.confidence, PkMatchConfidence.none);
  });

  test('empty inputs', () {
    expect(matcher.suggest([], []), isEmpty);
    expect(matcher.suggest([_local(id: 'l1', name: 'Alice')], []), isEmpty);
    final suggestions =
        matcher.suggest([], [_pk(id: 'pk1', name: 'Alice')]);
    expect(suggestions.first.confidence, PkMatchConfidence.none);
  });
}
