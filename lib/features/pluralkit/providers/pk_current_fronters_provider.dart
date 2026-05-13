import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';

/// Lazily fetches the current PK fronters switch for display in the pull-only
/// heads-up banner on the setup screen.
///
/// Returns `null` on any failure (network error, timeout, not connected) —
/// callers should suppress the banner when null.
///
/// Cache semantics: `ref.keepAlive()` keeps the result alive until the
/// [ProviderContainer] (or its subtree) disposes. In practice this means the
/// result lives as long as the [ProviderScope] that wraps the setup screen —
/// i.e. until the user acknowledges mapping or backs out of setup. That
/// satisfies the spec requirement ("cache lifetime: until the user acknowledges
/// mapping or backs out of setup") without a manual invalidation step.
///
/// MVP compromise: we do not invalidate on systemId change. If the user
/// disconnects and reconnects to a different PK system within the same
/// [ProviderScope] session the cached value could be stale. In the setup flow
/// this is extremely rare (the screen is typically fresh for each connect
/// attempt), and the banner is purely informational, so the risk is accepted.
final pkCurrentFrontersProvider = FutureProvider.autoDispose<PKSwitch?>((
  ref,
) async {
  // Keep alive for the duration of the enclosing ProviderScope so
  // re-entering the setup screen does not trigger a second PK API call.
  ref.keepAlive();

  final service = ref.read(pluralKitSyncServiceProvider);

  // Use buildClientIgnoringMappingGate so this works while mapping is pending
  // (which is exactly when the banner is shown).
  final client = await service.buildClientIgnoringMappingGate();
  if (client == null) return null;

  try {
    return await client
        .getCurrentFronters()
        .timeout(const Duration(seconds: 5));
  } on Object {
    return null;
  } finally {
    client.dispose();
  }
});
