import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

/// Helper to build a realistic Klipy API response body.
Map<String, dynamic> _buildResponse(List<Map<String, dynamic>> items) {
  return {
    'data': {
      'data': items,
    },
  };
}

/// A minimal valid GIF item with the nested file structure.
Map<String, dynamic> _gifItem({
  String id = '123',
  String title = 'funny cat',
}) {
  return {
    'id': id,
    'title': title,
    'type': 'gif',
    'file': {
      'xs': {
        'mp4': {
          'url': 'https://media.klipy.com/xs.mp4',
          'width': 100,
          'height': 80,
        },
        'gif': {
          'url': 'https://media.klipy.com/xs.gif',
          'width': 100,
          'height': 80,
        },
      },
    },
  };
}

void main() {
  // ════════════════════════════════════════════════════════════════════════════
  // GifSearchQueryNotifier
  // ════════════════════════════════════════════════════════════════════════════

  group('gifSearchQueryProvider', () {
    test('starts with empty string', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(gifSearchQueryProvider), '');
    });

    test('set() updates state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(gifSearchQueryProvider.notifier).set('cats');

      expect(container.read(gifSearchQueryProvider), 'cats');
    });

    test('clear() resets to empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(gifSearchQueryProvider.notifier).set('dogs');
      expect(container.read(gifSearchQueryProvider), 'dogs');

      container.read(gifSearchQueryProvider.notifier).clear();
      expect(container.read(gifSearchQueryProvider), '');
    });

    test('set() replaces previous value', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(gifSearchQueryProvider.notifier).set('cats');
      container.read(gifSearchQueryProvider.notifier).set('dogs');

      expect(container.read(gifSearchQueryProvider), 'dogs');
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // gifSearchResultsProvider
  // ════════════════════════════════════════════════════════════════════════════

  group('gifSearchResultsProvider', () {
    test('calls trending when query is empty', () async {
      Uri? capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode(_buildResponse([_gifItem()])),
          200,
        );
      });

      final container = ProviderContainer(
        overrides: [
          klipyServiceProvider.overrideWithValue(
            AsyncValue.data(
              KlipyService(
                baseUrl: 'https://relay.example/v1/gifs',
                httpClient: mockClient,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Query is empty by default — should call trending.
      final result = await container.read(gifSearchResultsProvider.future);

      expect(capturedUri, isNotNull);
      expect(capturedUri!.path, contains('/trending'));
      expect(result, hasLength(1));
      expect(result.first.id, '123');
    });

    test('calls search when query is non-empty', () async {
      Uri? capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode(_buildResponse([_gifItem(id: 'search-hit')])),
          200,
        );
      });

      final container = ProviderContainer(
        overrides: [
          klipyServiceProvider.overrideWithValue(
            AsyncValue.data(
              KlipyService(
                baseUrl: 'https://relay.example/v1/gifs',
                httpClient: mockClient,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(gifSearchQueryProvider.notifier).set('funny');

      final result = await container.read(gifSearchResultsProvider.future);

      expect(capturedUri, isNotNull);
      expect(capturedUri!.path, contains('/search'));
      expect(capturedUri!.queryParameters['q'], 'funny');
      expect(result, hasLength(1));
      expect(result.first.id, 'search-hit');
    });

    test('returns empty list when API returns no results', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(_buildResponse([])), 200);
      });

      final container = ProviderContainer(
        overrides: [
          klipyServiceProvider.overrideWithValue(
            AsyncValue.data(
              KlipyService(
                baseUrl: 'https://relay.example/v1/gifs',
                httpClient: mockClient,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(gifSearchResultsProvider.future);
      expect(result, isEmpty);
    });

    test('propagates API errors', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Rate limited', 429);
      });

      final container = ProviderContainer(
        overrides: [
          klipyServiceProvider.overrideWithValue(
            AsyncValue.data(
              KlipyService(
                baseUrl: 'https://relay.example/v1/gifs',
                httpClient: mockClient,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Listen to keep the autoDispose provider alive and wait for it to
      // settle into an error state.
      container.listen(gifSearchResultsProvider, (_, _) {},
          fireImmediately: true);

      // Give the async provider time to complete.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final result = container.read(gifSearchResultsProvider);
      expect(result.hasError, isTrue);
      expect(result.error, isA<KlipyRateLimitError>());
    });
  });

  group('GIF consent gating', () {
    test('attachment stays visible until explicitly declined', () {
      final container = ProviderContainer(
        overrides: [
          gifServiceConfigProvider.overrideWithValue(
            const AsyncValue.data(
              GifServiceConfig(
                enabled: true,
                apiBaseUrl: 'https://relay.example/v1/gifs',
                mediaProxyEnabled: false,
              ),
            ),
          ),
          gifConsentStateProvider.overrideWith((_) => GifConsentState.unknown),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(gifAttachmentEnabledProvider), isTrue);
      expect(container.read(gifConsentRequiredProvider), isTrue);
    });

    test('attachment hides after decline', () {
      final container = ProviderContainer(
        overrides: [
          gifServiceConfigProvider.overrideWithValue(
            const AsyncValue.data(
              GifServiceConfig(
                enabled: true,
                apiBaseUrl: 'https://relay.example/v1/gifs',
                mediaProxyEnabled: false,
              ),
            ),
          ),
          gifConsentStateProvider.overrideWith((_) => GifConsentState.declined),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(gifAttachmentEnabledProvider), isFalse);
      expect(container.read(gifRenderingEnabledProvider), isTrue);
      expect(container.read(gifConsentRequiredProvider), isFalse);
    });

    test('relay-disabled GIFs never require consent', () {
      final container = ProviderContainer(
        overrides: [
          gifServiceConfigProvider.overrideWithValue(
            const AsyncValue.data(GifServiceConfig.disabled()),
          ),
          gifConsentStateProvider.overrideWith((_) => GifConsentState.unknown),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(gifAttachmentEnabledProvider), isFalse);
      expect(container.read(gifRenderingEnabledProvider), isFalse);
      expect(container.read(gifConsentRequiredProvider), isFalse);
    });

    test('enabled consent keeps attachment visible without re-prompting', () {
      final container = ProviderContainer(
        overrides: [
          gifServiceConfigProvider.overrideWithValue(
            const AsyncValue.data(
              GifServiceConfig(
                enabled: true,
                apiBaseUrl: 'https://relay.example/v1/gifs',
                mediaProxyEnabled: false,
              ),
            ),
          ),
          gifConsentStateProvider.overrideWith((_) => GifConsentState.enabled),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(gifAttachmentEnabledProvider), isTrue);
      expect(container.read(gifRenderingEnabledProvider), isTrue);
      expect(container.read(gifConsentRequiredProvider), isFalse);
    });
  });
}
