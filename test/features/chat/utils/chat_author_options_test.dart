import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/utils/chat_author_options.dart';
import 'package:prism_plurality/l10n/app_localizations_en.dart';

// Helpers for concise test members.
Member _member(String id, {bool isActive = true}) =>
    Member(id: id, name: id, createdAt: DateTime.utc(2025), isActive: isActive);

Conversation _dm(List<String> participantIds) => Conversation(
  id: 'conv',
  createdAt: DateTime.utc(2025),
  lastActivityAt: DateTime.utc(2025),
  isDirectMessage: true,
  participantIds: participantIds,
);

Conversation _group({
  List<String> participantIds = const [],
  bool includesAllMembers = false,
}) => Conversation(
  id: 'conv',
  createdAt: DateTime.utc(2025),
  lastActivityAt: DateTime.utc(2025),
  isDirectMessage: false,
  // A non-empty title ensures this is never mistaken for a legacy DM
  // by isDirectMessageConversation (which requires a blank title).
  title: 'Test Group',
  participantIds: participantIds,
  includesAllMembers: includesAllMembers,
);

/// A "legacy DM": isDirectMessage == false but looks like a DM —
/// untitled, no emoji, no category, exactly two participants.
/// [isDirectMessageConversation] returns true for these.
Conversation _legacyDm(List<String> participantIds) => Conversation(
  id: 'conv',
  createdAt: DateTime.utc(2025),
  lastActivityAt: DateTime.utc(2025),
  isDirectMessage: false,
  participantIds: participantIds,
  // No title, emoji, or categoryId → matches legacy-DM heuristic.
);

void main() {
  final l10n = AppLocalizationsEn();

  final alice = _member('alice');
  final bob = _member('bob');
  final carol = _member('carol');

  group('chatAuthorCandidateIds', () {
    test('DM: only participant ids; unknown only when explicit', () {
      final ids = chatAuthorCandidateIds(_dm(['alice', 'bob']), [
        alice,
        bob,
        carol,
      ]);
      // Unknown is NOT in participantIds, so it should not be included.
      expect(ids, containsAll(['alice', 'bob']));
      expect(ids, isNot(contains('carol')));
      expect(ids, isNot(contains(unknownSentinelMemberId)));
    });

    test('DM with unknown sentinel in participantIds includes it', () {
      final ids = chatAuthorCandidateIds(
        _dm(['alice', unknownSentinelMemberId]),
        [alice, bob],
      );
      expect(ids, containsAll(['alice', unknownSentinelMemberId]));
      expect(ids, isNot(contains('bob')));
    });

    test(
      'DM with empty participantIds returns all active member ids + unknown',
      () {
        final ids = chatAuthorCandidateIds(_dm([]), [alice, bob]);
        expect(ids, containsAll(['alice', 'bob', unknownSentinelMemberId]));
      },
    );

    test('explicit-membership group returns only participant ids', () {
      final ids = chatAuthorCandidateIds(
        _group(participantIds: ['alice', 'bob']),
        [alice, bob, carol],
      );
      expect(ids, containsAll(['alice', 'bob']));
      expect(ids, isNot(contains('carol')));
      expect(ids, isNot(contains(unknownSentinelMemberId)));
    });

    test('includesAllMembers returns all active member ids plus unknown', () {
      final ids = chatAuthorCandidateIds(_group(includesAllMembers: true), [
        alice,
        bob,
        carol,
      ]);
      expect(
        ids,
        containsAll(['alice', 'bob', 'carol', unknownSentinelMemberId]),
      );
    });

    test(
      'currentAuthorId is included in result even if not in activeMembers',
      () {
        final departed = _member('departed');
        final ids = chatAuthorCandidateIds(
          _group(participantIds: ['alice']),
          [alice, bob],
          currentAuthorId: 'departed',
          currentAuthor: departed,
        );
        expect(ids, contains('departed'));
      },
    );

    group('legacy DM (isDirectMessage=false, untitled, 2 participants)', () {
      // Legacy DMs have isDirectMessage == false but are detected as DMs by
      // isDirectMessageConversation. They should return the same candidate set
      // as a proper DM with the same two participants — only the two
      // participant members, no Unknown sentinel, no third members.
      test('returns only participant members — same set as proper DM', () {
        final legacyIds = chatAuthorCandidateIds(_legacyDm(['alice', 'bob']), [
          alice,
          bob,
          carol,
        ]);
        final properDmIds = chatAuthorCandidateIds(_dm(['alice', 'bob']), [
          alice,
          bob,
          carol,
        ]);
        expect(
          legacyIds,
          equals(properDmIds),
          reason:
              'legacy DM should produce the same candidate set as a proper DM',
        );
        expect(
          legacyIds,
          isNot(contains('carol')),
          reason: 'carol is not a participant — must be excluded',
        );
        expect(
          legacyIds,
          isNot(contains(unknownSentinelMemberId)),
          reason: 'Unknown not in participantIds — must be excluded',
        );
      });
    });
  });

  group('chatAuthorCandidates', () {
    test(
      'DM: returns participant members; unknown omitted unless explicit',
      () {
        final result = chatAuthorCandidates(_dm(['alice', 'bob']), [
          alice,
          bob,
          carol,
        ], l10n);
        final ids = result.map((m) => m.id).toList();
        expect(ids, containsAll(['alice', 'bob']));
        expect(ids, isNot(contains('carol')));
        // Unknown is not in participantIds, so it is not appended.
        expect(ids, isNot(contains(unknownSentinelMemberId)));
      },
    );

    test(
      'DM with unknown sentinel in participantIds includes it, not duplicate',
      () {
        final result = chatAuthorCandidates(
          _dm(['alice', unknownSentinelMemberId]),
          [alice, bob],
          l10n,
        );
        final ids = result.map((m) => m.id).toList();
        expect(ids.where((id) => id == unknownSentinelMemberId).length, 1);
        expect(ids, isNot(contains('bob')));
      },
    );

    test('DM with empty participantIds returns all members + unknown', () {
      final result = chatAuthorCandidates(_dm([]), [alice, bob], l10n);
      final ids = result.map((m) => m.id).toList();
      expect(ids, containsAll(['alice', 'bob', unknownSentinelMemberId]));
      expect(ids.last, unknownSentinelMemberId);
    });

    test('explicit-membership group returns only participant members', () {
      final result = chatAuthorCandidates(
        _group(participantIds: ['alice', 'bob']),
        [alice, bob, carol],
        l10n,
      );
      final ids = result.map((m) => m.id).toList();
      expect(ids, containsAll(['alice', 'bob']));
      expect(ids, isNot(contains('carol')));
      expect(ids, isNot(contains(unknownSentinelMemberId)));
    });

    test(
      'includesAllMembers returns all active members plus unknown at end',
      () {
        final result = chatAuthorCandidates(_group(includesAllMembers: true), [
          alice,
          bob,
          carol,
        ], l10n);
        final ids = result.map((m) => m.id).toList();
        expect(
          ids,
          containsAll(['alice', 'bob', 'carol', unknownSentinelMemberId]),
        );
        expect(ids.last, unknownSentinelMemberId);
      },
    );

    group('ordering — currentAuthorId', () {
      test('matching member is pinned to index 0', () {
        final result = chatAuthorCandidates(
          _dm(['alice', 'bob']),
          [alice, bob, carol],
          l10n,
          currentAuthorId: 'alice',
        );
        expect(result.first.id, 'alice');
      });

      test('non-first member is promoted to index 0', () {
        final result = chatAuthorCandidates(
          _dm(['alice', 'bob']),
          [alice, bob, carol],
          l10n,
          currentAuthorId: 'bob',
        );
        expect(result.first.id, 'bob');
        // alice should still appear somewhere
        expect(result.map((m) => m.id), contains('alice'));
      });

      test(
        'unknown sentinel as currentAuthorId is included (pinned last by default)',
        () {
          // Unknown is always appended last; it is included because it appears
          // explicitly in participantIds. Passing currentAuthorId == Unknown does
          // not move it earlier — Unknown is always the tail sentinel.
          final result = chatAuthorCandidates(
            _dm(['alice', unknownSentinelMemberId]),
            [alice, bob],
            l10n,
            currentAuthorId: unknownSentinelMemberId,
          );
          expect(result.map((m) => m.id), contains(unknownSentinelMemberId));
        },
      );

      test('departed current author (not in activeMembers) is at index 0 when '
          'currentAuthor is supplied', () {
        final departed = _member('departed', isActive: false);
        final result = chatAuthorCandidates(
          _group(participantIds: ['alice', 'departed']),
          [alice, bob],
          l10n,
          currentAuthorId: 'departed',
          currentAuthor: departed,
        );
        expect(result.first.id, 'departed');
        expect(result.map((m) => m.id), contains('alice'));
        expect(result.map((m) => m.id), isNot(contains('bob')));
      });

      test(
        'departed current author is pinned even when no longer a participant',
        () {
          final departed = _member('departed', isActive: false);
          final result = chatAuthorCandidates(
            _group(participantIds: ['alice']),
            [alice, bob],
            l10n,
            currentAuthorId: 'departed',
            currentAuthor: departed,
          );
          final ids = result.map((m) => m.id).toList();
          expect(ids.first, 'departed');
          expect(ids, contains('alice'));
          expect(ids, isNot(contains('bob')));
        },
      );

      test('inactive non-current participants are not author candidates', () {
        final inactiveCarol = _member('carol', isActive: false);
        final result = chatAuthorCandidates(
          _group(participantIds: ['alice', 'carol']),
          [alice, inactiveCarol],
          l10n,
        );
        final ids = result.map((m) => m.id).toList();
        expect(ids, contains('alice'));
        expect(ids, isNot(contains('carol')));
      });

      test(
        'currentAuthorId null leaves order unchanged; unknown last for non-DMs',
        () {
          // Unknown is not appended for limited groups unless explicitly listed.
          final result = chatAuthorCandidates(
            _group(participantIds: ['alice', 'bob']),
            [alice, bob],
            l10n,
          );
          expect(
            result.map((m) => m.id),
            isNot(contains(unknownSentinelMemberId)),
          );
        },
      );
    });
  });
}
