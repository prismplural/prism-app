class CastPollVoteCommand {
  const CastPollVoteCommand({
    required this.pollId,
    required this.optionId,
    required this.memberId,
    this.responseText,
  });

  final String pollId;
  final String optionId;
  final String memberId;
  final String? responseText;
}
