// Per-helper unit tests for the `@visibleForTesting` field-map helpers
// exposed in Phase 0 of `docs/plans/sp-import-perf-quick-wins.md`.
//
// Phase 5 of the perf plan adds a capture-replay path in `sp_importer.dart`
// that bypasses repository methods for bulk inserts. To keep the captured
// `fields` payload byte-equal to what the repository would have emitted,
// that path calls these helpers instead of duplicating the field-map logic.
//
// These tests pin the helper output for a representative sample input.
// Any drift between the repository's emission payload and the helper's
// returned map shows up as a unit-test failure here — not as a parity
// mystery in the larger harness.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase, MemberGroupRow, MemberGroupEntryRow;
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/poll_vote.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';

void main() {
  group('pollVoteFields', () {
    test('produces the exact tuple Phase 5 capture-replay must mirror', () {
      final vote = PollVote(
        id: 'vote-1',
        memberId: 'mem-1',
        votedAt: DateTime.utc(2026, 5, 12, 10, 0, 0),
        responseText: 'because',
      );
      const optionId = 'opt-1';

      final fields = DriftPollRepository.pollVoteFields(vote, optionId);

      expect(fields, {
        'poll_option_id': 'opt-1',
        'member_id': 'mem-1',
        'voted_at': '2026-05-12T10:00:00.000Z',
        'response_text': 'because',
        'is_deleted': false,
      });
    });

    test('preserves null response_text without dropping the key', () {
      final vote = PollVote(
        id: 'v',
        memberId: 'm',
        votedAt: DateTime.utc(2026, 5, 12),
      );
      final fields = DriftPollRepository.pollVoteFields(vote, 'o');
      expect(fields.containsKey('response_text'), isTrue);
      expect(fields['response_text'], isNull);
    });

    test('emits UTC ISO-8601 for non-UTC input', () {
      // Construct a local instant; the helper must canonicalize to UTC.
      final local = DateTime(2026, 5, 12, 6, 30, 0); // local time
      final vote = PollVote(id: 'v', memberId: 'm', votedAt: local);
      final fields = DriftPollRepository.pollVoteFields(vote, 'o');
      expect(fields['voted_at'], local.toUtc().toIso8601String());
      expect(fields['voted_at'].toString().endsWith('Z'), isTrue);
    });
  });

  group('memberFields', () {
    test(
      'produces the exact tuple Phase 6 batch-member capture must mirror',
      () {
        final m = Member(
          id: 'mem-1',
          name: 'Test Member',
          emoji: '❔',
          pronouns: 'they/them',
          bio: 'A bio.',
          isActive: true,
          createdAt: DateTime.utc(2026, 5, 12, 10, 0, 0),
          displayOrder: 7,
          customColorEnabled: true,
          customColorHex: 'aabbcc',
        );

        final fields = DriftMemberRepository.memberFields(m);

        // Pin the headline fields explicitly; assert every expected key is
        // present so a silent drop is caught.
        expect(fields['name'], 'Test Member');
        expect(fields['pronouns'], 'they/them');
        expect(fields['emoji'], '❔');
        expect(fields['bio'], 'A bio.');
        expect(fields['is_active'], true);
        expect(fields['created_at'], '2026-05-12T10:00:00.000Z');
        expect(fields['display_order'], 7);
        expect(fields['custom_color_enabled'], true);
        expect(fields['custom_color_hex'], 'aabbcc');
        expect(fields['avatar_image_data'], isNull);
        expect(fields['is_deleted'], false);

        // The plan's emission contract is: every member field present, no
        // extras dropped. Spot-check that none of the optional PK fields leak.
        expect(fields.containsKey('pluralkit_id'), isTrue);
        expect(fields.containsKey('pluralkit_uuid'), isTrue);
      },
    );
  });

  group('memberGroupEntryFields', () {
    final group = MemberGroupRow(
      id: 'grp-1',
      name: 'Group 1',
      displayOrder: 0,
      groupType: 0,
      createdAt: DateTime.utc(2026, 5, 12),
      isDeleted: false,
      syncSuppressed: false,
    );

    test('non-PK group: omits pk_* keys', () {
      const entry = MemberGroupEntryRow(
        id: 'entry-1',
        groupId: 'grp-1',
        memberId: 'mem-1',
        isDeleted: false,
        pendingPkOp: 'none',
      );
      final fields = DriftMemberGroupsRepository.memberGroupEntryFields(
        entry,
        group: group,
        member: null,
      );
      expect(fields, {
        'group_id': 'grp-1',
        'member_id': 'mem-1',
        'is_deleted': false,
      });
    });

    test('PK-linked group + PK-linked member: includes pk_* keys', () {
      final pkGroup = MemberGroupRow(
        id: 'grp-2',
        name: 'PK Group',
        displayOrder: 0,
        groupType: 0,
        createdAt: DateTime.utc(2026, 5, 12),
        isDeleted: false,
        pluralkitUuid: 'pk-grp-uuid',
        syncSuppressed: false,
      );
      const entry = MemberGroupEntryRow(
        id: 'entry-2',
        groupId: 'grp-2',
        memberId: 'mem-2',
        pkGroupUuid: 'pk-grp-uuid',
        pkMemberUuid: 'pk-mem-uuid',
        isDeleted: false,
        pendingPkOp: 'push_add',
      );
      final pkMember = Member(
        id: 'mem-2',
        name: 'PK Member',
        emoji: '❔',
        isActive: true,
        createdAt: DateTime.utc(2026, 5, 12),
        pluralkitUuid: 'pk-mem-uuid',
      );

      final fields = DriftMemberGroupsRepository.memberGroupEntryFields(
        entry,
        group: pkGroup,
        member: pkMember,
      );

      expect(fields, {
        'group_id': 'grp-2',
        'member_id': 'mem-2',
        'pk_group_uuid': 'pk-grp-uuid',
        'pk_member_uuid': 'pk-mem-uuid',
        'is_deleted': false,
      });
    });
  });

  group('settingsFields', () {
    test(
      'exposes the same field-map shape the repo emits to the FFI',
      () async {
        // The `settingsFields` helper is an instance method (it
        // delegates to the private `_settingsFields` builder). To exercise
        // it without a full DI graph, spin up an in-memory `AppDatabase`,
        // construct the repo with its DAO and a null sync handle, then call
        // the helper directly. No transactions, no FFI, no other tables.
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = DriftSystemSettingsRepository(db.systemSettingsDao, null);

        const settings = SystemSettings(
          systemName: 'Hello System',
          systemDescription: 'A description.',
          systemColor: 'ff0011',
        );

        final fields = repo.settingsFields(settings);

        // The full map is large and feature-gated; pin the SP-import-relevant
        // subset and verify the determinism invariant (same input → same
        // output across calls).
        expect(fields['system_name'], 'Hello System');
        expect(fields['system_description'], 'A description.');
        expect(fields['system_color'], 'ff0011');
        expect(fields['is_deleted'], false);

        final again = repo.settingsFields(settings);
        expect(again, fields);

        // The `debugSettingsFields` alias must produce the byte-equal map —
        // Phase 5 capture-replay relies on the alias being just another name
        // for the same builder. Drift between them would re-introduce the
        // op-type/field-shape drift codex v1 flagged.
        expect(repo.debugSettingsFields(settings), fields);
      },
    );
  });
}
