import 'package:flutter/foundation.dart';
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

/// Notifier for the GIF search query. Paired with an autoDispose results
/// provider so reopening the picker starts with a fresh trending grid.
class GifSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
  void clear() => state = '';
}

final gifSearchQueryProvider =
    NotifierProvider<GifSearchQueryNotifier, String>(
        GifSearchQueryNotifier.new);

// ---------------------------------------------------------------------------
// Search results
// ---------------------------------------------------------------------------

/// GIF search results — returns trending when query is empty, search results
/// otherwise. Auto-disposes when no longer watched.
final gifSearchResultsProvider =
    FutureProvider.autoDispose<List<KlipyGif>>((ref) async {
  // GIF feature disabled in release builds until relay proxy ships.
  if (kReleaseMode) return const [];
  final query = ref.watch(gifSearchQueryProvider);
  final service = ref.watch(klipyServiceProvider);

  if (query.isEmpty) {
    return service.trending();
  }
  return service.search(query);
});
