import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/chat/services/klipy_service.dart';

// ---------------------------------------------------------------------------
// Service provider
// ---------------------------------------------------------------------------

/// Singleton [KlipyService] instance, disposed with the container.
final klipyServiceProvider = Provider<KlipyService>((ref) {
  final service = KlipyService();
  ref.onDispose(service.dispose);
  return service;
});

// ---------------------------------------------------------------------------
// Search query state
// ---------------------------------------------------------------------------

/// Manages the current search query for the GIF picker.
class GifSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
  void clear() => state = '';
}

final gifSearchQueryProvider =
    NotifierProvider<GifSearchNotifier, String>(GifSearchNotifier.new);

// ---------------------------------------------------------------------------
// Search results
// ---------------------------------------------------------------------------

/// GIF search results — returns trending when query is empty, search results
/// otherwise. Auto-disposes when no longer watched.
final gifSearchResultsProvider =
    FutureProvider.autoDispose<List<KlipyGif>>((ref) async {
  final query = ref.watch(gifSearchQueryProvider);
  final service = ref.watch(klipyServiceProvider);

  if (query.isEmpty) {
    return service.trending();
  }
  return service.search(query);
});
