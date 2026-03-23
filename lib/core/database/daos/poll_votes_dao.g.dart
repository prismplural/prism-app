// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'poll_votes_dao.dart';

// ignore_for_file: type=lint
mixin _$PollVotesDaoMixin on DatabaseAccessor<AppDatabase> {
  $PollVotesTable get pollVotes => attachedDatabase.pollVotes;
  PollVotesDaoManager get managers => PollVotesDaoManager(this);
}

class PollVotesDaoManager {
  final _$PollVotesDaoMixin _db;
  PollVotesDaoManager(this._db);
  $$PollVotesTableTableManager get pollVotes =>
      $$PollVotesTableTableManager(_db.attachedDatabase, _db.pollVotes);
}
