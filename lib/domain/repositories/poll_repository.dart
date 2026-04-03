import 'package:prism_plurality/domain/models/poll.dart' as domain;
import 'package:prism_plurality/domain/models/poll_option.dart' as domain;
import 'package:prism_plurality/domain/models/poll_vote.dart' as domain;

abstract class PollRepository {
  Future<List<domain.Poll>> getAllPolls();
  Stream<List<domain.Poll>> watchAllPolls();
  Future<List<domain.Poll>> getActivePolls();
  Stream<List<domain.Poll>> watchActivePolls();
  Future<List<domain.Poll>> getClosedPolls();
  Future<domain.Poll?> getPollById(String id);
  Stream<domain.Poll?> watchPollById(String id);
  Future<void> createPoll(domain.Poll poll);
  Future<void> updatePoll(domain.Poll poll);
  Future<void> deletePoll(String id);
  Future<void> closePoll(String id);

  // Options
  Future<List<domain.PollOption>> getAllOptions();
  Future<List<domain.PollOption>> getOptionsForPoll(String pollId);
  Stream<List<domain.PollOption>> watchOptionsForPoll(String pollId);
  Future<void> createOption(domain.PollOption option, String pollId);
  Future<void> deleteOption(String id);

  // Votes
  Future<List<domain.PollVote>> getAllVotes();
  Future<List<domain.PollVote>> getVotesForOption(String optionId);
  Stream<List<domain.PollVote>> watchVotesForOption(String optionId);
  Future<void> castVote(domain.PollVote vote, String optionId);
  Future<void> removeVote(String id);
  Future<int> getCount();
}
