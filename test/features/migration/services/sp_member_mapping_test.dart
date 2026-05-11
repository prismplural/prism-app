import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/migration/services/sp_member_mapping.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

void main() {
  test('suggests persisted, PluralKit, and unique-name matches', () {
    final localPrevious = _member(id: 'local-previous', name: 'Old Name');
    final localPk = _member(
      id: 'local-pk',
      name: 'Different Name',
      pluralkitId: 'abcde',
    );
    final localName = _member(id: 'local-name', name: 'Casey');

    final suggestions = const SpMemberMatcher().suggest(
      spMembers: const [
        SpMember(id: 'sp-previous', name: 'Previous'),
        SpMember(id: 'sp-pk', name: 'Remote PK', pkId: 'abcde'),
        SpMember(id: 'sp-name', name: '  casey  '),
        SpMember(id: 'sp-new', name: 'New'),
      ],
      localMembers: [localPrevious, localPk, localName],
      persistedMemberMappings: const {'sp-previous': 'local-previous'},
    );

    expect(_matchFor(suggestions, 'sp-previous'), (
      localId: 'local-previous',
      confidence: SpMemberMatchConfidence.persistedMapping,
    ));
    expect(_matchFor(suggestions, 'sp-pk'), (
      localId: 'local-pk',
      confidence: SpMemberMatchConfidence.pluralKitId,
    ));
    expect(_matchFor(suggestions, 'sp-name'), (
      localId: 'local-name',
      confidence: SpMemberMatchConfidence.exactName,
    ));
    expect(_matchFor(suggestions, 'sp-new'), (
      localId: null,
      confidence: SpMemberMatchConfidence.none,
    ));
  });

  test('does not suggest duplicate SP members for the same local member', () {
    final suggestions = const SpMemberMatcher().suggest(
      spMembers: const [
        SpMember(id: 'sp-a', name: 'Alice', pkId: 'abcde'),
        SpMember(id: 'sp-b', name: 'Alice', pkId: 'abcde'),
      ],
      localMembers: [
        _member(id: 'local-a', name: 'Alice', pluralkitId: 'abcde'),
      ],
    );

    expect(suggestions, hasLength(2));
    expect(suggestions.every((s) => s.suggestedLocal == null), isTrue);
    expect(
      suggestions.map((s) => s.confidence),
      everyElement(SpMemberMatchConfidence.none),
    );
  });

  test(
    'ignores colliding persisted mappings instead of reusing a local twice',
    () {
      final suggestions = const SpMemberMatcher().suggest(
        spMembers: const [
          SpMember(id: 'sp-a', name: 'Alpha'),
          SpMember(id: 'sp-b', name: 'Beta'),
        ],
        localMembers: [_member(id: 'local-a', name: 'Alpha')],
        persistedMemberMappings: const {'sp-a': 'local-a', 'sp-b': 'local-a'},
      );

      expect(_matchFor(suggestions, 'sp-a'), (
        localId: 'local-a',
        confidence: SpMemberMatchConfidence.exactName,
      ));
      expect(_matchFor(suggestions, 'sp-b'), (
        localId: null,
        confidence: SpMemberMatchConfidence.none,
      ));
    },
  );
}

Member _member({
  required String id,
  required String name,
  String? pluralkitId,
}) {
  return Member(
    id: id,
    name: name,
    createdAt: DateTime.utc(2024),
    pluralkitId: pluralkitId,
  );
}

({String? localId, SpMemberMatchConfidence confidence}) _matchFor(
  List<SpMemberMatchSuggestion> suggestions,
  String spId,
) {
  final match = suggestions.singleWhere((s) => s.spMember.id == spId);
  return (localId: match.suggestedLocal?.id, confidence: match.confidence);
}
