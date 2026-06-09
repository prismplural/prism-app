import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/repositories/conversation_repository.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';

import '../../../helpers/fake_repositories.dart';

Conversation _conversation(String id) => Conversation(
  id: id,
  title: id,
  createdAt: DateTime.utc(2026, 1, 1),
  lastActivityAt: DateTime.utc(2026, 1, 1),
  participantIds: const ['alice'],
);

class _RecordingConversationRepository extends FakeConversationRepository {
  _RecordingConversationRepository(this.activity);

  final List<ConversationActivity> activity;
  final requestedLimits = <int?>[];

  @override
  Future<List<ConversationActivity>> getConversationActivityForMember(
    String memberId, {
    int? limit,
  }) async {
    requestedLimits.add(limit);
    return limit == null ? activity : activity.take(limit).toList();
  }
}

void main() {
  test('member conversation preview provider asks for one extra row', () async {
    final repo = _RecordingConversationRepository([
      (conversation: _conversation('one'), messageCount: 10),
      (conversation: _conversation('two'), messageCount: 8),
      (conversation: _conversation('three'), messageCount: 6),
      (conversation: _conversation('four'), messageCount: 4),
      (conversation: _conversation('five'), messageCount: 2),
    ]);
    final container = ProviderContainer(
      overrides: [conversationRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final preview = await container.read(
      memberConversationPreviewActivityProvider('alice').future,
    );

    expect(repo.requestedLimits, [memberConversationPreviewCount + 1]);
    expect(preview.map((item) => item.conversation.id), [
      'one',
      'two',
      'three',
      'four',
    ]);
  });

  test('member conversations provider preserves activity ordering', () async {
    final repo = _RecordingConversationRepository([
      (conversation: _conversation('most-active'), messageCount: 10),
      (conversation: _conversation('less-active'), messageCount: 2),
    ]);
    final container = ProviderContainer(
      overrides: [conversationRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final conversations = await container.read(
      memberConversationsProvider('alice').future,
    );

    expect(repo.requestedLimits, [null]);
    expect(conversations.map((conversation) => conversation.id), [
      'most-active',
      'less-active',
    ]);
  });
}
