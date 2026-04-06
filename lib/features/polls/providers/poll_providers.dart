import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/core/services/error_providers.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/polls/models/cast_poll_vote_command.dart';
import 'package:prism_plurality/features/polls/models/poll_summary.dart';
import 'package:prism_plurality/features/polls/services/poll_mutation_service.dart';

final pollMutationServiceProvider = Provider<PollMutationService>((ref) {
  final database = ref.watch(databaseProvider);
  final errorReportingService = ref.watch(errorReportingServiceProvider);
  return PollMutationService(
    database: database,
    repository: ref.watch(pollRepositoryProvider),
    runner: MutationRunner.forDatabase(
      database,
      errorReportingService: errorReportingService,
    ),
  );
});

final _pollClockProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  while (true) {
    await Future<void>.delayed(const Duration(minutes: 1));
    yield DateTime.now();
  }
});

/// Watches all polls ordered by creation date.
final allPollsProvider = StreamProvider.autoDispose<List<PollSummary>>((ref) {
  final service = ref.watch(pollMutationServiceProvider);
  return service.watchPollSummaries();
});

/// Watches active polls (not closed and not expired).
final activePollsProvider =
    StreamProvider.autoDispose<List<PollSummary>>((ref) {
  final service = ref.watch(pollMutationServiceProvider);
  final now = ref.watch(_pollClockProvider).value ?? DateTime.now();
  return service.watchPollSummaries().map((polls) {
    return polls.where((poll) {
      return !poll.isClosed && !poll.isExpiredAt(now);
    }).toList();
  });
});

/// Watches closed polls (closed or expired).
final closedPollsProvider =
    StreamProvider.autoDispose<List<PollSummary>>((ref) {
  final service = ref.watch(pollMutationServiceProvider);
  final now = ref.watch(_pollClockProvider).value ?? DateTime.now();
  return service.watchPollSummaries().map((polls) {
    return polls.where((p) {
      return p.isClosed || p.isExpiredAt(now);
    }).toList();
  });
});

/// Watches a single poll by ID (with options and votes).
final pollByIdProvider = StreamProvider.autoDispose.family<Poll?, String>((
  ref,
  id,
) {
  final repo = ref.watch(pollRepositoryProvider);
  return repo.watchPollById(id);
});

/// Options for a specific poll.
final pollOptionsProvider = StreamProvider.autoDispose
    .family<List<PollOption>, String>((ref, pollId) {
      final service = ref.watch(pollMutationServiceProvider);
      return service.watchOptionsWithVotesForPoll(pollId);
    });

/// Votes for a specific option.
final optionVotesProvider = StreamProvider.autoDispose
    .family<List<PollVote>, String>((ref, optionId) {
      final repo = ref.watch(pollRepositoryProvider);
      return repo.watchVotesForOption(optionId);
    });

/// Currently selected "voting as" member for polls.
final votingAsProvider = NotifierProvider<VotingAsNotifier, String?>(
  VotingAsNotifier.new,
);

class VotingAsNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setMember(String? memberId) => state = memberId;
}

/// Poll actions notifier.
class PollNotifier extends Notifier<void> {
  static const _uuid = Uuid();

  @override
  void build() {}

  Future<Poll> createPoll({
    required String question,
    String? description,
    required List<String> optionTexts,
    List<String?>? optionColorHexes,
    bool isAnonymous = false,
    bool allowsMultipleVotes = false,
    DateTime? expiresAt,
    bool addOtherOption = false,
  }) async {
    final service = ref.read(pollMutationServiceProvider);
    final pollId = _uuid.v4();
    final optionIds = [for (var i = 0; i < optionTexts.length; i++) _uuid.v4()];
    final createdAt = DateTime.now();

    return _unwrap(
      service.createPoll(
        question: question,
        description: description,
        optionTexts: optionTexts,
        optionColorHexes: optionColorHexes,
        isAnonymous: isAnonymous,
        allowsMultipleVotes: allowsMultipleVotes,
        expiresAt: expiresAt,
        addOtherOption: addOtherOption,
        pollId: pollId,
        createdAt: createdAt,
        optionIds: optionIds,
        otherOptionId: _uuid.v4(),
      ),
    );
  }

  Future<void> addVote({
    required String pollId,
    required String optionId,
    required String memberId,
    String? responseText,
  }) async {
    final service = ref.read(pollMutationServiceProvider);
    await _unwrap(
      service.castVote(
        CastPollVoteCommand(
          pollId: pollId,
          optionId: optionId,
          memberId: memberId,
          responseText: responseText,
        ),
      ),
    );
  }

  Future<void> removeVote(String voteId) async {
    await _unwrap(ref.read(pollMutationServiceProvider).removeVote(voteId));
  }

  Future<void> closePoll(String pollId) async {
    await _unwrap(ref.read(pollMutationServiceProvider).closePoll(pollId));
  }

  Future<void> deletePoll(String pollId) async {
    await _unwrap(ref.read(pollMutationServiceProvider).deletePoll(pollId));
  }

  Future<T> _unwrap<T>(Future<MutationResult<T>> resultFuture) async {
    final result = await resultFuture;
    return result.when(
      success: (data) => data,
      failure: (error) => throw error,
    );
  }
}

final pollNotifierProvider = NotifierProvider<PollNotifier, void>(
  PollNotifier.new,
);
