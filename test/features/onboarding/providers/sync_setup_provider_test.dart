import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/sync_setup_provider.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePrismSyncHandleNotifier extends PrismSyncHandleNotifier {
  _FakePrismSyncHandleNotifier(this.handle);

  final ffi.PrismSyncHandle handle;
  String? lastRelayUrl;

  @override
  Future<ffi.PrismSyncHandle?> build() async => handle;

  @override
  Future<ffi.PrismSyncHandle> createHandle({required String relayUrl}) async {
    lastRelayUrl = relayUrl;
    return handle;
  }
}

void main() {
  group('SyncSetupNotifier.proceedToEnterPhrase URL validation', () {
    late _FakePrismSyncHandleNotifier fakeHandleNotifier;

    setUp(() {
      fakeHandleNotifier = _FakePrismSyncHandleNotifier(
        const _FakePrismSyncHandle(),
      );
    });

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: [
          prismSyncHandleProvider.overrideWith(() => fakeHandleNotifier),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<SyncSetupState> runValidation(String relayUrl) async {
      final container = makeContainer();
      final notifier = container.read(syncSetupProvider.notifier);
      notifier.setRelayUrl(relayUrl);
      await notifier.proceedToEnterPhrase();
      return container.read(syncSetupProvider);
    }

    test('accepts https:// for public hosts', () async {
      final state = await runValidation('https://example.com');
      expect(state.error, isNull);
      expect(state.step, SyncSetupStep.enterPhrase);
      expect(fakeHandleNotifier.lastRelayUrl, 'https://example.com');
    });

    test('rejects http:// for public hosts', () async {
      final state = await runValidation('http://example.com');
      expect(state.error, isNotNull);
      expect(state.step, SyncSetupStep.intro);
      expect(fakeHandleNotifier.lastRelayUrl, isNull);
    });

    test('accepts http://localhost:<port>', () async {
      final state = await runValidation('http://localhost:8080');
      expect(state.error, isNull);
      expect(state.step, SyncSetupStep.enterPhrase);
      expect(fakeHandleNotifier.lastRelayUrl, 'http://localhost:8080');
    });

    test('accepts http://127.0.0.1:<port>', () async {
      final state = await runValidation('http://127.0.0.1:8080');
      expect(state.error, isNull);
      expect(state.step, SyncSetupStep.enterPhrase);
      expect(fakeHandleNotifier.lastRelayUrl, 'http://127.0.0.1:8080');
    });

    test('accepts http://[::1]:<port>', () async {
      final state = await runValidation('http://[::1]:8080');
      expect(state.error, isNull);
      expect(state.step, SyncSetupStep.enterPhrase);
      expect(fakeHandleNotifier.lastRelayUrl, 'http://[::1]:8080');
    });
  });
}
