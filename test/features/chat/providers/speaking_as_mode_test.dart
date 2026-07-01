import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/preferences/composer_default_member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

class _FakeMode extends ComposerDefaultMemberNotifier {
  _FakeMode(this._value);
  final ComposerDefaultMember _value;
  @override
  Future<ComposerDefaultMember> build() async => _value;
}

class _FakeLastUsed extends LastUsedSpeakingAsMemberNotifier {
  _FakeLastUsed(this._value);
  final String? _value;
  @override
  Future<String?> build() async => _value;
}

Member _member(String id) =>
    Member(id: id, name: id, createdAt: DateTime(2026, 5, 7));

FrontingSession _session(String memberId, DateTime start) => FrontingSession(
  id: 'session-$memberId',
  memberId: memberId,
  startTime: start,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> makeContainer({
    required ComposerDefaultMember mode,
    String? lastUsed,
    required List<FrontingSession> sessions,
    required List<Member> members,
  }) async {
    final container = ProviderContainer(
      overrides: [
        activeSessionsProvider.overrideWithValue(AsyncValue.data(sessions)),
        activeMembersProvider.overrideWithValue(AsyncValue.data(members)),
        activeMemberListProvider.overrideWithValue(AsyncValue.data(members)),
        chatLogsFrontProvider.overrideWithValue(false),
        composerDefaultMemberProvider.overrideWith(() => _FakeMode(mode)),
        lastUsedSpeakingAsMemberProvider.overrideWith(
          () => _FakeLastUsed(lastUsed),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(composerDefaultMemberProvider.future);
    await container.read(lastUsedSpeakingAsMemberProvider.future);
    return container;
  }

  test(
    'latestFronter mode keeps the legacy most-recent-front default',
    () async {
      final container = await makeContainer(
        mode: ComposerDefaultMember.latestFronter,
        lastUsed: 'alice',
        sessions: [
          _session('alice', DateTime(2026, 5, 7, 10)),
          _session('bob', DateTime(2026, 5, 7, 11)),
        ],
        members: [_member('alice'), _member('bob')],
      );
      // bob fronted last — latestFronter ignores lastUsed='alice'.
      expect(container.read(speakingAsProvider), 'bob');
    },
  );

  test('lastUsed mode returns the remembered member when selectable', () async {
    final container = await makeContainer(
      mode: ComposerDefaultMember.lastUsed,
      lastUsed: 'alice',
      sessions: [
        _session('alice', DateTime(2026, 5, 7, 10)),
        _session('bob', DateTime(2026, 5, 7, 11)),
      ],
      members: [_member('alice'), _member('bob')],
    );
    // Default would be bob; lastUsed='alice' wins.
    expect(container.read(speakingAsProvider), 'alice');
  });

  test(
    'lastUsed mode falls back to fronter when remembered member is stale',
    () async {
      final container = await makeContainer(
        mode: ComposerDefaultMember.lastUsed,
        lastUsed: 'ghost', // not in active members
        sessions: [_session('bob', DateTime(2026, 5, 7, 11))],
        members: [_member('bob')],
      );
      // Never returns null (would trip the viewer gate) — falls to the fronter.
      expect(container.read(speakingAsProvider), 'bob');
    },
  );

  test(
    'lastUsed mode does not trust the stored id while the roster is loading',
    () async {
      // Security: a cold-stored id must not become speakingAs before the active
      // roster confirms it — fall back to the live fronter instead.
      final container = ProviderContainer(
        overrides: [
          activeSessionsProvider.overrideWithValue(
            AsyncValue.data([_session('bob', DateTime(2026, 5, 7, 11))]),
          ),
          // Roster still loading → activeMemberIds is null.
          activeMembersProvider.overrideWithValue(const AsyncValue.loading()),
          activeMemberListProvider.overrideWithValue(
            const AsyncValue.loading(),
          ),
          chatLogsFrontProvider.overrideWithValue(false),
          composerDefaultMemberProvider.overrideWith(
            () => _FakeMode(ComposerDefaultMember.lastUsed),
          ),
          lastUsedSpeakingAsMemberProvider.overrideWith(
            () => _FakeLastUsed('alice'),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(composerDefaultMemberProvider.future);
      await container.read(lastUsedSpeakingAsMemberProvider.future);

      // Falls to the live fronter, not the unvalidated stored 'alice'.
      expect(container.read(speakingAsProvider), 'bob');
    },
  );

  test('lastUsed mode with no memory falls back to fronter', () async {
    final container = await makeContainer(
      mode: ComposerDefaultMember.lastUsed,
      lastUsed: null,
      sessions: [_session('bob', DateTime(2026, 5, 7, 11))],
      members: [_member('bob')],
    );
    expect(container.read(speakingAsProvider), 'bob');
  });

  test(
    'askEachTime mode resolves to a safe fronter default (non-null)',
    () async {
      final container = await makeContainer(
        mode: ComposerDefaultMember.askEachTime,
        lastUsed: 'alice',
        sessions: [
          _session('alice', DateTime(2026, 5, 7, 10)),
          _session('bob', DateTime(2026, 5, 7, 11)),
        ],
        members: [_member('alice'), _member('bob')],
      );
      // The picker prompt is driven by the UI; the resolved default stays the
      // safe fronter so the viewer gate never sees null.
      expect(container.read(speakingAsProvider), 'bob');
    },
  );

  test(
    'latestFronter mode clears explicit selection when fronting sessions change',
    () async {
      final sessions = StreamController<List<FrontingSession>>.broadcast();
      addTearDown(sessions.close);
      final container = ProviderContainer(
        overrides: [
          activeSessionsProvider.overrideWith((ref) => sessions.stream),
          activeMembersProvider.overrideWithValue(
            AsyncValue.data([
              _member('alice'),
              _member('bob'),
              _member('carol'),
            ]),
          ),
          activeMemberListProvider.overrideWithValue(
            AsyncValue.data([
              _member('alice'),
              _member('bob'),
              _member('carol'),
            ]),
          ),
          chatLogsFrontProvider.overrideWithValue(false),
          composerDefaultMemberProvider.overrideWith(
            () => _FakeMode(ComposerDefaultMember.latestFronter),
          ),
          lastUsedSpeakingAsMemberProvider.overrideWith(
            () => _FakeLastUsed(null),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(composerDefaultMemberProvider.future);

      // Start: alice and bob fronting, bob started later.
      final bobSelected = Completer<void>();
      final sub = container.listen<String?>(speakingAsProvider, (prev, next) {
        if (next == 'bob' && !bobSelected.isCompleted) {
          bobSelected.complete();
        }
      });
      sessions.add([
        _session('alice', DateTime(2026, 5, 7, 10)),
        _session('bob', DateTime(2026, 5, 7, 11)),
      ]);
      await bobSelected.future;
      expect(container.read(speakingAsProvider), 'bob');

      // User explicitly picks alice — honored immediately.
      container.read(speakingAsProvider.notifier).setMember('alice');
      expect(container.read(speakingAsProvider), 'alice');

      // Fronting sessions change: carol starts fronting, alice and bob end.
      // latestFronter mode should clear the stale explicit selection.
      final carolSelected = Completer<void>();
      container.listen<String?>(speakingAsProvider, (prev, next) {
        if (next == 'carol' && !carolSelected.isCompleted) {
          carolSelected.complete();
        }
      });
      sessions.add([_session('carol', DateTime(2026, 5, 7, 12))]);
      await carolSelected.future;
      sub.close();
      expect(container.read(speakingAsProvider), 'carol');
    },
  );

  test('setMember persists the choice for last-used', () async {
    final container = await makeContainer(
      mode: ComposerDefaultMember.latestFronter,
      lastUsed: null,
      sessions: const [],
      members: [_member('alice'), _member('bob')],
    );
    container.read(speakingAsProvider.notifier).setMember('alice');
    // Let the best-effort unawaited write settle.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // Persisted to SharedPreferences via the real notifier path (mocked store).
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('prism.pref.last_used_speaking_as_member'), 'alice');
  });
}
