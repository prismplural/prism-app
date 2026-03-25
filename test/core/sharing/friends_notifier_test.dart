import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/domain/models/friend_record.dart';
import 'package:prism_plurality/domain/repositories/friends_repository.dart';

/// Minimal fake that exposes a controllable stream and tracks listener count.
class _FakeFriendsRepository implements FriendsRepository {
  final _controller = StreamController<List<FriendRecord>>.broadcast();
  int activeListeners = 0;

  Stream<List<FriendRecord>> get stream => _controller.stream;

  void emit(List<FriendRecord> records) => _controller.add(records);

  @override
  Stream<List<FriendRecord>> watchAll() {
    activeListeners++;
    return _controller.stream.map((records) => records).doOnCancel(() {
      activeListeners--;
    });
  }

  void dispose() => _controller.close();

  // ── Unused stubs ──
  @override
  Future<void> createFriend(FriendRecord friend) async {}
  @override
  Future<void> deleteFriend(String id) async {}
  @override
  Future<FriendRecord?> getById(String id) async => null;
  @override
  Future<void> updateFriend(FriendRecord friend) async {}
}

/// Extension to track cancellation via doOnCancel.
extension _StreamDoOnCancel<T> on Stream<T> {
  Stream<T> doOnCancel(void Function() onCancel) {
    late StreamController<T> controller;
    StreamSubscription<T>? sub;

    controller = StreamController<T>(
      onListen: () {
        sub = listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () {
        onCancel();
        sub?.cancel();
      },
    );

    return controller.stream;
  }
}

void main() {
  late _FakeFriendsRepository fakeRepo;

  setUp(() {
    fakeRepo = _FakeFriendsRepository();
  });

  tearDown(() {
    fakeRepo.dispose();
  });

  test('subscription is cancelled when provider is disposed', () async {
    final container = ProviderContainer(
      overrides: [
        friendsRepositoryProvider.overrideWithValue(fakeRepo),
      ],
    );
    addTearDown(container.dispose);

    // Read the provider to trigger build() and the stream subscription.
    final sub = container.listen(friendsProvider, (_, _) {});

    // Let the stream subscription establish.
    await Future<void>.delayed(Duration.zero);

    expect(fakeRepo.activeListeners, 1);

    // Close the listener and invalidate, which disposes the notifier.
    sub.close();
    container.invalidate(friendsProvider);
    await Future<void>.delayed(Duration.zero);

    expect(fakeRepo.activeListeners, 0,
        reason: 'Stream subscription should be cancelled on dispose');
  });

  test('rebuild does not leak additional subscriptions', () async {
    final container = ProviderContainer(
      overrides: [
        friendsRepositoryProvider.overrideWithValue(fakeRepo),
      ],
    );
    addTearDown(container.dispose);

    final sub = container.listen(friendsProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);

    expect(fakeRepo.activeListeners, 1);

    // Invalidate forces a rebuild — the old subscription should be cancelled
    // before the new one is created.
    container.invalidate(friendsProvider);
    await Future<void>.delayed(Duration.zero);

    expect(fakeRepo.activeListeners, 1,
        reason: 'Old subscription should be cancelled before new one starts');

    sub.close();
  });

  test('emitted records are converted to Friend models', () async {
    final container = ProviderContainer(
      overrides: [
        friendsRepositoryProvider.overrideWithValue(fakeRepo),
      ],
    );
    addTearDown(container.dispose);

    final sub = container.listen(friendsProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);

    // Initially empty.
    expect(container.read(friendsProvider), isEmpty);

    // Emit a record.
    final now = DateTime.now();
    fakeRepo.emit([
      FriendRecord(
        id: 'f1',
        displayName: 'Alice',
        publicKeyHex: 'abc123',
        createdAt: now,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    final friends = container.read(friendsProvider);
    expect(friends, hasLength(1));
    expect(friends.first.id, 'f1');
    expect(friends.first.displayName, 'Alice');

    sub.close();
  });
}
