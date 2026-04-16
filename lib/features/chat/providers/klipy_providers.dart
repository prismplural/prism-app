import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

final klipyHttpClientOverrideProvider = Provider<http.Client?>((_) => null);

final gifServiceConfigProvider = FutureProvider.autoDispose<GifServiceConfig>((
  ref,
) async {
  final handle = ref.watch(prismSyncHandleProvider).value;
  final relayUrl = ref.watch(relayUrlProvider).value;
  if (handle == null || relayUrl == null || relayUrl.isEmpty) {
    return const GifServiceConfig.disabled();
  }

  final json = await ffi.fetchGifServiceConfig(handle: handle);
  return GifServiceConfig.fromJson(
    jsonDecode(json) as Map<String, dynamic>,
    relayUrl: relayUrl,
  );
});

final klipyServiceProvider = FutureProvider.autoDispose<KlipyService?>((
  ref,
) async {
  ref.keepAlive();
  final config = await ref.watch(gifServiceConfigProvider.future);
  final baseUrl = config.apiBaseUrl;
  if (!config.enabled || baseUrl == null || baseUrl.isEmpty) return null;

  final service = KlipyService(
    baseUrl: baseUrl,
    httpClient: ref.watch(klipyHttpClientOverrideProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

class GifSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
  void clear() => state = '';
}

final gifSearchQueryProvider =
    NotifierProvider.autoDispose<GifSearchQueryNotifier, String>(
      GifSearchQueryNotifier.new,
    );

final gifSearchResultsProvider = FutureProvider.autoDispose<List<KlipyGif>>((
  ref,
) async {
  final query = ref.watch(gifSearchQueryProvider);
  final service = await ref.watch(klipyServiceProvider.future);
  if (service == null) return const [];

  if (query.isEmpty) {
    return service.trending();
  }
  return service.search(query);
});

final gifAttachmentEnabledProvider = Provider<bool>((ref) {
  final consent = ref.watch(gifConsentStateProvider);
  final config = ref.watch(gifServiceConfigProvider).asData?.value;
  return config?.enabled == true && consent != GifConsentState.declined;
});

final gifRenderingEnabledProvider = Provider<bool>((ref) {
  final consent = ref.watch(gifConsentStateProvider);
  final config = ref.watch(gifServiceConfigProvider).asData?.value;
  return config?.enabled == true && consent == GifConsentState.enabled;
});

final gifConsentRequiredProvider = Provider<bool>((ref) {
  final consent = ref.watch(gifConsentStateProvider);
  final config = ref.watch(gifServiceConfigProvider).asData?.value;
  return config?.enabled == true && consent == GifConsentState.unknown;
});
