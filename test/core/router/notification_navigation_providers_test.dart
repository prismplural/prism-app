import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/router/notification_navigation_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';

class _LifetimeTransport extends LocalNotificationService {
  final launch = Completer<String?>();
  final firstLaunchRead = Completer<void>();

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> getLaunchPayload() {
    if (!firstLaunchRead.isCompleted) firstLaunchRead.complete();
    return launch.future;
  }
}

void main() {
  test(
    'owner scope disposal rejects delayed launch and all late public mutations',
    () async {
      final container = ProviderContainer();
      final intents = container.read(notificationNavigationProvider.notifier);
      intents.receiveCallback('prism:fronting:v1');
      final claim = intents.claim()!;
      final launch = Completer<String?>();
      final launchRequested = Completer<void>();
      void Function(String?)? sink;
      final bootstrap = NotificationTapBootstrap(
        intents: intents,
        attachSink: (value) => sink = value,
        initialize: () async {},
        getLaunchPayload: () {
          launchRequested.complete();
          return launch.future;
        },
      );
      final started = bootstrap.start();
      await launchRequested.future;
      container.dispose();
      launch.complete('prism:reminder:scheduled:old');
      await started;
      sink!('prism:reminder:scheduled:late');
      intents.receiveLaunch(
        'prism:fronting:v1',
        contextEpoch: intents.contextEpoch,
      );
      intents.bindAuthorizedContext('late-account');
      intents.clearContext();
      intents.beginContextChange();
      intents.endContextChange();
      intents.release(claim);
      expect(intents.isClosed, isTrue);
      expect(intents.pending, isNull);
      expect(intents.claim(), isNull);
      expect(intents.complete(claim), isFalse);
      expect(intents.isCurrent(claim), isFalse);
    },
  );

  test(
    'invalidated bootstrap cannot deliver old launch or detach newer callback',
    () async {
      final service = _LifetimeTransport();
      final container = ProviderContainer(
        overrides: [
          localNotificationServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(service.dispose);
      Object? oldFailure;
      final oldStart = container.read(notificationTapBootstrapProvider.future);
      unawaited(
        oldStart.then<void>(
          (_) {},
          onError: (Object e, StackTrace _) {
            oldFailure = e;
          },
        ),
      );
      await service.firstLaunchRead.future;
      final oldSink = service.onNotificationTap!;
      container.invalidate(notificationTapBootstrapProvider);
      final newStart = container.read(notificationTapBootstrapProvider.future);
      final newerSink = service.onNotificationTap!;
      expect(identical(oldSink, newerSink), isFalse);
      oldSink('prism:reminder:scheduled:stale-callback');
      newerSink('prism:reminder:scheduled:newer');
      service.launch.complete('prism:reminder:scheduled:stale-launch');
      await newStart;
      final intents = container.read(notificationNavigationProvider.notifier);
      expect(intents.pending?.reminderId, 'newer');
      expect(intents.callbackVersion, 1);
      expect(oldFailure, isNull);
      final claim = intents.claim()!;
      expect(intents.complete(claim), isTrue);
      newerSink('prism:reminder:scheduled:later');
      expect(intents.pending?.reminderId, 'later');
    },
  );

  test(
    'reset finally after owner disposal does not mask original failure with state write',
    () async {
      final container = ProviderContainer();
      final intents = container.read(notificationNavigationProvider.notifier);
      final resetBoundary = Completer<void>();
      final original = StateError('Synthetic original reset error');
      Future<void> resetOwner() async {
        intents.beginContextChange();
        try {
          await resetBoundary.future;
          throw original;
        } finally {
          // Same public barrier API used by real reset/replace/sync-reset owners.
          intents.endContextChange();
        }
      }

      final resetting = resetOwner();
      container.dispose();
      final failure = expectLater(resetting, throwsA(same(original)));
      resetBoundary.complete();
      await failure;
      expect(intents.pending, isNull);
      expect(intents.claim(), isNull);
    },
  );
  test(
    'nested reset owners suppress all receipt and claims until outer end',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final intents = container.read(notificationNavigationProvider.notifier);
      intents.receiveCallback('prism:fronting:v1');
      final stale = intents.claim()!;
      final oldEpoch = intents.contextEpoch;
      intents.beginContextChange();
      intents.beginContextChange();
      intents.receiveCallback('prism:reminder:scheduled:during');
      intents.receiveLaunch(
        'prism:reminder:scheduled:during',
        contextEpoch: intents.contextEpoch,
      );
      expect(intents.pending, isNull);
      expect(intents.claim(), isNull);
      intents.endContextChange();
      expect(intents.contextChanging, isTrue);
      intents.receiveCallback('prism:fronting:v1');
      expect(intents.pending, isNull);
      intents.endContextChange();
      expect(intents.contextChanging, isFalse);
      expect(intents.complete(stale), isFalse);
      intents.receiveLaunch(
        'prism:reminder:scheduled:old',
        contextEpoch: oldEpoch,
      );
      expect(intents.pending, isNull);
      intents.receiveCallback('prism:reminder:scheduled:after');
      expect(intents.claim()?.intent.reminderId, 'after');
    },
  );

  test('pre-reset launch resolving after reset ends is still stale', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final intents = container.read(notificationNavigationProvider.notifier);
    final launch = Completer<String?>();
    final bootstrap = NotificationTapBootstrap(
      intents: intents,
      attachSink: (_) {},
      initialize: () async {},
      getLaunchPayload: () => launch.future,
    );
    final started = bootstrap.start();
    intents.beginContextChange();
    intents.endContextChange();
    launch.complete('prism:reminder:scheduled:old');
    await started;
    expect(intents.pending, isNull);
    intents.receiveCallback('prism:fronting:v1');
    expect(intents.claim(), isNotNull);
  });

  test('unbalanced context end fails closed without counter underflow', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final intents = container.read(notificationNavigationProvider.notifier);
    expect(intents.endContextChange, throwsStateError);
    expect(intents.contextChanging, isTrue);
    intents.receiveCallback('prism:fronting:v1');
    expect(intents.pending, isNull);
    expect(intents.claim(), isNull);
  });
  test('intake and bootstrap cannot resolve protected providers', () async {
    var protectedReads = 0;
    Never forbidden() {
      protectedReads++;
      throw StateError('Protected provider resolved before authorization');
    }

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) => forbidden()),
        databaseReadyProvider.overrideWith((ref) => forbidden()),
        remindersRepositoryProvider.overrideWith((ref) => forbidden()),
        prismSyncHandleProvider.overrideWith(() => _ForbiddenHandle(forbidden)),
        syncIdProvider.overrideWith((ref) => forbidden()),
        syncDeviceIdProvider.overrideWith((ref) => forbidden()),
        syncDeviceSecretPresentProvider.overrideWith((ref) => forbidden()),
        syncWrappedDekPresentProvider.overrideWith((ref) => forbidden()),
      ],
    );
    addTearDown(container.dispose);
    final intents = container.read(notificationNavigationProvider.notifier);
    void Function(String?)? sink;
    var initializations = 0;
    var launches = 0;
    final bootstrap = NotificationTapBootstrap(
      intents: intents,
      attachSink: (value) => sink = value,
      initialize: () async {
        initializations++;
        expect(sink, isNotNull);
      },
      getLaunchPayload: () async {
        launches++;
        return 'prism:reminder:scheduled:synthetic-id';
      },
    );
    await Future.wait([bootstrap.start(), bootstrap.start()]);
    await bootstrap.start();
    expect(initializations, 1);
    expect(launches, 1);
    expect(intents.pending?.reminderId, 'synthetic-id');
    expect(protectedReads, 0);
  });

  for (final validCallback in [true, false]) {
    test('only accepted callback supersedes launch: $validCallback', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final intents = container.read(notificationNavigationProvider.notifier);
      void Function(String?)? sink;
      final launch = Completer<String?>();
      final bootstrap = NotificationTapBootstrap(
        intents: intents,
        attachSink: (value) => sink = value,
        initialize: () async {},
        getLaunchPayload: () => launch.future,
      );
      final started = bootstrap.start();
      sink!(validCallback ? 'prism:reminder:scheduled:newer' : '/members');
      launch.complete('prism:reminder:scheduled:older');
      await started;
      expect(intents.pending?.reminderId, validCallback ? 'newer' : 'older');
    });
  }

  test(
    'bootstrap overlap merges; recurrence after consumption is accepted',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final intents = container.read(notificationNavigationProvider.notifier);
      void Function(String?)? sink;
      final bootstrap = NotificationTapBootstrap(
        intents: intents,
        attachSink: (value) => sink = value,
        initialize: () async => sink!('prism:reminder:scheduled:id'),
        getLaunchPayload: () async => 'prism:reminder:scheduled:id',
      );
      await bootstrap.start();
      final claim = intents.claim()!;
      expect(intents.claim(), isNull);
      expect(intents.complete(claim), isTrue);
      expect(intents.claim(), isNull);
      sink!('prism:reminder:scheduled:id');
      expect(intents.claim(), isNotNull);
    },
  );

  test(
    'context clear rejects delayed launch; known identity change rejects claim',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final intents = container.read(notificationNavigationProvider.notifier);
      final launch = Completer<String?>();
      final bootstrap = NotificationTapBootstrap(
        intents: intents,
        attachSink: (_) {},
        initialize: () async {},
        getLaunchPayload: () => launch.future,
      );
      final started = bootstrap.start();
      intents.clearContext();
      launch.complete('prism:reminder:scheduled:old');
      await started;
      expect(intents.pending, isNull);
      intents.receiveCallback('prism:fronting:v1');
      intents.bindAuthorizedContext(
        null,
      ); // First unknown context is not a switch.
      final claim = intents.claim()!;
      intents.bindAuthorizedContext('new-account');
      expect(intents.complete(claim), isFalse);
      expect(intents.pending, isNull);
    },
  );
}

class _ForbiddenHandle extends PrismSyncHandleNotifier {
  _ForbiddenHandle(this.forbidden);
  final Never Function() forbidden;
  @override
  Future<ffi.PrismSyncHandle?> build() async => forbidden();
}
