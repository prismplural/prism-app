import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_prefs_keys.dart';

/// AsyncNotifier that exposes and manages the "first sync deferred" flag for
/// the currently connected PK system.
///
/// The flag is stored in SharedPreferences keyed by systemId so reconnects to
/// a different PK system get a clean slate. [PkFirstSyncDeferredNotifier.clear]
/// removes the flag permanently (user dismissed the banner).
class PkFirstSyncDeferredNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final dao = ref.watch(pluralKitSyncDaoProvider);
    final row = await dao.getSyncState();
    final systemId = row.systemId;
    if (systemId == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(PkPrefsKeys.firstSyncDeferred(systemId)) ?? false;
  }

  /// Dismiss the deferred-sync banner permanently for this PK system.
  Future<void> clear() async {
    final dao = ref.read(pluralKitSyncDaoProvider);
    final row = await dao.getSyncState();
    final systemId = row.systemId;
    if (systemId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PkPrefsKeys.firstSyncDeferred(systemId));
    state = const AsyncValue.data(false);
  }
}

final pkFirstSyncDeferredProvider =
    AsyncNotifierProvider<PkFirstSyncDeferredNotifier, bool>(
      PkFirstSyncDeferredNotifier.new,
    );
