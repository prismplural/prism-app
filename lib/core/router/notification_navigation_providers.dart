import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_notification_service.dart';
import 'notification_navigation.dart';

/// Intake never initializes credentials, repositories, native sync or routing.
/// Context is supplied by an already-authorized consumer or the reset owner.
class NotificationNavigation extends Notifier<int> {
  final _queue = PendingNotificationIntents();
  int _contextEpoch = 0;
  int _callbackVersion = 0;
  int _contextChangeDepth = 0;
  bool _contextBound = false;
  bool _closed = false;
  String? _accountId;

  @override
  int build() {
    ref.onDispose(() {
      _closed = true;
      _contextEpoch++;
      _contextBound = false;
      _accountId = null;
      _queue.clear();
    });
    return 0;
  }

  NotificationIntent? get pending => _queue.pending;
  int get contextEpoch => _contextEpoch;
  int get callbackVersion => _callbackVersion;
  bool get isClosed => _closed;
  bool get contextChanging => _closed || _contextChangeDepth != 0;

  void receiveCallback(String? payload) {
    if (contextChanging || NotificationIntent.parse(payload) == null) return;
    _callbackVersion++;
    if (_queue.receive(payload)) state++;
  }

  void receiveLaunch(String? payload, {required int contextEpoch}) {
    if (contextChanging || contextEpoch != _contextEpoch) return;
    if (_queue.receive(payload)) state++;
  }

  void bindAuthorizedContext(String? accountId) {
    if (_closed) return;
    if (_contextBound && _accountId != accountId) clearContext();
    _contextBound = true;
    _accountId = accountId;
  }

  void clearContext() {
    if (_closed) return;
    _contextEpoch++;
    _contextBound = false;
    _accountId = null;
    _queue.clear();
    state++;
  }

  void beginContextChange() {
    if (_closed) return;
    _contextChangeDepth++;
    clearContext();
  }

  void endContextChange() {
    if (_closed) return;
    if (_contextChangeDepth == 0) {
      // Programming errors fail closed, never underflow/reopen intake.
      _contextChangeDepth = 1;
      clearContext();
      throw StateError('Unbalanced notification context change');
    }
    clearContext();
    _contextChangeDepth--;
  }

  NotificationIntentClaim? claim() => contextChanging ? null : _queue.claim();
  bool isCurrent(NotificationIntentClaim claim) =>
      !contextChanging && _queue.isCurrent(claim);
  void release(NotificationIntentClaim claim) {
    if (!_closed) _queue.release(claim);
  }

  bool complete(NotificationIntentClaim claim) {
    if (contextChanging || !_queue.complete(claim)) return false;
    state++;
    return true;
  }
}

final notificationNavigationProvider =
    NotifierProvider<NotificationNavigation, int>(NotificationNavigation.new);

/// Normal app startup watches this before database loading. Its only dependency
/// is the notification transport: no protected storage or sync initialization.
final notificationTapBootstrapProvider = FutureProvider<void>((ref) async {
  final intents = ref.read(notificationNavigationProvider.notifier);
  final service = ref.read(localNotificationServiceProvider);
  final bootstrap = NotificationTapBootstrap(
    intents: intents,
    attachSink: (sink) => service.onNotificationTap = sink,
    initialize: service.initialize,
    getLaunchPayload: service.getLaunchPayload,
  );
  ref.onDispose(bootstrap.dispose);
  await bootstrap.start();
});

/// Platform adapter functions are supplied by the notification owner; this
/// bootstrap has no access to DB, account, permission or native-sync providers.
/// The shell must await [start] before consuming, merging callback/launch overlap
/// into the same bounded slot. No durable exactly-once delivery is implied.
class NotificationTapBootstrap {
  NotificationTapBootstrap({
    required this.intents,
    required this.attachSink,
    required this.initialize,
    required this.getLaunchPayload,
  });

  final NotificationNavigation intents;
  final void Function(void Function(String?)) attachSink;
  final Future<void> Function() initialize;
  final Future<String?> Function() getLaunchPayload;
  Future<void>? _started;
  bool _disposed = false;

  bool get _active => !_disposed && !intents.isClosed;

  void dispose() => _disposed = true;

  Future<void> start() {
    if (!_active) return Future.value();
    return _started ??= _start();
  }

  Future<void> _start() async {
    final epoch = intents.contextEpoch;
    final callbackVersion = intents.callbackVersion;
    if (!_active) return;
    attachSink((payload) {
      if (_active) intents.receiveCallback(payload);
    });
    try {
      await initialize();
      if (!_active) return;
      final payload = await getLaunchPayload();
      if (!_active) return;
      // Only valid callbacks can supersede launch details. Malformed callback
      // input must not discard a legitimate cold-launch target.
      if (intents.callbackVersion != callbackVersion) return;
      intents.receiveLaunch(payload, contextEpoch: epoch);
    } catch (_) {
      if (_active) rethrow;
    }
  }
}
