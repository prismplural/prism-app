import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/poll.dart' as domain;
import 'package:prism_plurality/domain/models/poll_option.dart' as domain;
import 'package:prism_plurality/features/polls/models/cast_poll_vote_command.dart';
import 'package:prism_plurality/features/polls/services/poll_mutation_service.dart';

void main() {
  for (final anonymous in [true, false]) {
    for (final multiple in [true, false]) {
      test('Other answers survive reopen and revote '
          '(anonymous=$anonymous, multiple=$multiple)', () async {
        final directory = await Directory.systemTemp.createTemp(
          'poll-answers-',
        );
        final file = File('${directory.path}/polls.sqlite');
        var db = AppDatabase(NativeDatabase(file));
        addTearDown(() async {
          await db.close();
          await directory.delete(recursive: true);
        });

        DriftPollRepository repository() => DriftPollRepository(
          db.pollsDao,
          db.pollOptionsDao,
          db.pollVotesDao,
          null,
        );
        PollMutationService service() => PollMutationService(
          database: db,
          repository: repository(),
          runner: MutationRunner(transactionRunner: db.transaction),
        );

        await repository().createPoll(
          domain.Poll(
            id: 'poll',
            question: 'Choose an outing',
            createdAt: DateTime(2026, 4, 15),
            isAnonymous: anonymous,
            allowsMultipleVotes: multiple,
            options: const [
              domain.PollOption(
                id: 'other',
                text: 'Other',
                isOtherOption: true,
              ),
              domain.PollOption(id: 'park', text: 'Park'),
            ],
          ),
        );
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        Future<void> cast(String member, String option, String? answer) async {
          final result = await service().castVote(
            CastPollVoteCommand(
              pollId: 'poll',
              optionId: option,
              memberId: member,
              responseText: answer,
            ),
          );
          expect(result.isSuccess, isTrue, reason: '${result.failureOrNull}');
        }

        await cast('alex', 'other', 'Library');
        await cast('bea', 'other', 'Museum');
        final initial = await repository().getVotesForOption('other');
        final oldAlexId = initial.singleWhere((v) => v.memberId == 'alex').id;
        expect(
          initial.map((v) => v.responseText),
          unorderedEquals(['Library', 'Museum']),
        );
        final creates = captured.where(
          (op) =>
              op.table == 'poll_votes' && op.opType == SyncRecordOpType.create,
        );
        expect(
          creates.map((op) => op.fields['response_text']),
          unorderedEquals(['Library', 'Museum']),
        );
        // Anonymity is a UI projection rule, not identity-free storage.
        expect(
          creates.map((op) => op.fields['member_id']),
          unorderedEquals(['alex', 'bea']),
        );

        await db.close();
        db = AppDatabase(NativeDatabase(file));
        expect(
          (await repository().getPollById('poll'))!.isAnonymous,
          anonymous,
        );
        expect(
          (await repository().getVotesForOption(
            'other',
          )).map((v) => v.responseText),
          unorderedEquals(['Library', 'Museum']),
        );
        final hydrated = await service()
            .watchOptionsWithVotesForPoll('poll')
            .first;
        expect(
          hydrated
              .singleWhere((o) => o.id == 'other')
              .votes
              .map((v) => v.responseText),
          unorderedEquals(['Library', 'Museum']),
        );

        captured.clear();
        await cast('alex', 'other', 'Aquarium');
        final edited = await repository().getVotesForOption('other');
        expect(
          edited.map((v) => v.responseText),
          unorderedEquals(['Aquarium', 'Museum']),
        );
        expect(
          captured.any(
            (op) =>
                op.entityId == oldAlexId &&
                op.opType == SyncRecordOpType.delete,
          ),
          isTrue,
        );
        expect(
          captured
              .singleWhere((op) => op.opType == SyncRecordOpType.create)
              .fields['response_text'],
          'Aquarium',
        );

        await cast('alex', 'park', null);
        final remaining = await repository().getVotesForOption('other');
        expect(
          remaining.map((v) => v.responseText),
          unorderedEquals(multiple ? ['Aquarium', 'Museum'] : ['Museum']),
        );
        expect(
          (await repository().getVotesForOption('park')).single.memberId,
          'alex',
        );

        // Invalid option and closed-poll edits must not erase persisted answers.
        final invalid = await service().castVote(
          const CastPollVoteCommand(
            pollId: 'poll',
            optionId: 'missing',
            memberId: 'bea',
            responseText: 'Should not replace Museum',
          ),
        );
        expect(invalid.isFailure, isTrue);
        await repository().closePoll('poll');
        final closed = await service().castVote(
          const CastPollVoteCommand(
            pollId: 'poll',
            optionId: 'other',
            memberId: 'bea',
            responseText: 'Should not replace Museum',
          ),
        );
        expect(closed.isFailure, isTrue);
        expect(
          (await repository().getVotesForOption(
            'other',
          )).singleWhere((v) => v.memberId == 'bea').responseText,
          'Museum',
        );

        await db.close();
        db = AppDatabase(NativeDatabase(file));
        expect(
          (await repository().getVotesForOption(
            'other',
          )).map((v) => v.responseText),
          unorderedEquals(multiple ? ['Aquarium', 'Museum'] : ['Museum']),
        );
      });
    }
  }
}
