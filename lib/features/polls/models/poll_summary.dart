class PollSummary {
  const PollSummary({
    required this.id,
    required this.question,
    required this.isAnonymous,
    required this.allowsMultipleVotes,
    required this.isClosed,
    required this.expiresAt,
    required this.createdAt,
    required this.optionCount,
    required this.voteCount,
  });

  final String id;
  final String question;
  final bool isAnonymous;
  final bool allowsMultipleVotes;
  final bool isClosed;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final int optionCount;
  final int voteCount;

  bool isExpiredAt(DateTime now) {
    return expiresAt != null && expiresAt!.isBefore(now);
  }
}
