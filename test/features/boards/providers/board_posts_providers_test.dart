import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

Member _member(String id) =>
    Member(id: id, name: id, createdAt: DateTime(2024, 1, 1));

FrontingSession _session(String id, String memberId) => FrontingSession(
  id: id,
  memberId: memberId,
  startTime: DateTime(2024, 1, 1),
);

void main() {
  group('currentFronterMemberIdsProvider', () {
    test('excludes fronting sessions for tombstoned members', () {
      final container = ProviderContainer(
        overrides: [
          activeSessionsProvider.overrideWithValue(
            AsyncValue.data([
              _session('s1', 'live'),
              _session('s2', 'deleted'),
            ]),
          ),
          activeMembersProvider.overrideWithValue(
            AsyncValue.data([_member('live')]),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentFronterMemberIdsProvider), ['live']);
    });
  });
}
