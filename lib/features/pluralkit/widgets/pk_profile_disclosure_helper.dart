import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_system_profile_disclosure.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

/// Shows the PluralKit system profile disclosure sheet, if applicable.
///
/// Fires only when all of these conditions hold:
/// - [syncState] is connected and has no sync error.
/// - [mode] is [PkSyncMode.fullSync].
/// - [direction] has `pullEnabled == true`.
/// - The PK system has at least one non-empty profile field.
/// - The sheet has not been shown before for this system (one-shot sentinel
///   in SharedPreferences).
///
/// This is a free function (no widget state) so it can be called from
/// both [PluralKitSetupScreen] and [PkMappingScreen] without duplication.
Future<void> maybeShowPkProfileDisclosure({
  required BuildContext context,
  required WidgetRef ref,
  required PluralKitSyncState syncState,
  required PkSyncMode mode,
  required PkSyncDirection direction,
}) async {
  // Guard conditions.
  if (!syncState.isConnected || syncState.syncError != null) return;
  if (mode != PkSyncMode.fullSync) return;
  if (!direction.pullEnabled) return;

  final notifier = ref.read(pluralKitSyncProvider.notifier);
  final PKSystem? pkSystem;
  try {
    pkSystem = await notifier.fetchSystemProfile();
  } catch (_) {
    return;
  }
  if (pkSystem == null) return;

  // Short-circuit if PK has nothing worth offering.
  final anyField =
      (pkSystem.name?.isNotEmpty ?? false) ||
      (pkSystem.description?.isNotEmpty ?? false) ||
      (pkSystem.tag?.isNotEmpty ?? false) ||
      (pkSystem.avatarUrl?.isNotEmpty ?? false);
  if (!anyField) return;

  // One-shot per PK system: once a user decides (import or skip) we don't
  // show the sheet again on subsequent reconnects with the same systemId.
  final prefs = await SharedPreferences.getInstance();
  final sentinelKey = 'pk_profile_disclosure_shown_${pkSystem.id}';
  if (prefs.getBool(sentinelKey) == true) return;

  if (!context.mounted) return;

  final currentSettings = await ref
      .read(systemSettingsRepositoryProvider)
      .getSettings();
  if (!context.mounted) return;

  final accepted = await PrismSheet.show<Set<PkProfileField>?>(
    context: context,
    builder: (sheetCtx) => PkSystemProfileDisclosureSheet(
      pkSystem: pkSystem!,
      currentPrismSettings: currentSettings,
      onConfirm: (selected) => Navigator.of(sheetCtx).pop(selected),
      onSkip: () => Navigator.of(sheetCtx).pop(<PkProfileField>{}),
    ),
  );

  await prefs.setBool(sentinelKey, true);

  if (accepted != null && accepted.isNotEmpty) {
    await notifier.adoptSystemProfile(pk: pkSystem, accepted: accepted);
  }
}
