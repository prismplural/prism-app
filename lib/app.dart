import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'core/database/database_encryption.dart';
import 'core/database/database_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/media/bio_media_reconciler.dart';
import 'core/services/media/orphan_media_reconciler.dart';
import 'core/services/notification_providers.dart';
import 'core/services/reminder_scheduler_service.dart';
import 'core/services/screen_privacy_controller.dart';
import 'core/sync/prism_sync_providers.dart';
import 'features/pluralkit/providers/pk_sync_event_log_provider.dart';
import 'features/fronting/migration/providers/fronting_migration_providers.dart';
import 'features/fronting/providers/fronting_session_repair_provider.dart';
import 'features/habits/providers/habit_providers.dart';
import 'features/onboarding/providers/onboarding_providers.dart';
import 'domain/models/system_settings.dart';
import 'features/settings/providers/settings_providers.dart';
import 'shared/theme/app_colors.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/prism_shapes.dart' as ui_shapes;
import 'shared/widgets/prism_keyboard_dismiss_scope.dart';
import 'shared/widgets/prism_toast.dart';

class PrismApp extends ConsumerStatefulWidget {
  const PrismApp({super.key});

  @override
  ConsumerState<PrismApp> createState() => _PrismAppState();
}

class _PrismAppState extends ConsumerState<PrismApp> {
  late final AppLifecycleListener _appLifecycleListener;
  bool _ranOrphanMediaReconcile = false;
  bool _ranBioMediaReconcile = false;

  @override
  void initState() {
    super.initState();
    _appLifecycleListener = AppLifecycleListener(onResume: _onResume);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _repairPrimaryDatabaseKeySlot();
    });
  }

  /// Run the on-disk media cache sweep exactly once per app launch, after
  /// `prismSyncHandleProvider` has resolved (so we don't race a still-loading
  /// sync layer materializing inbound media). Fires regardless of whether
  /// the handle is null (no sync configured) or non-null (sync up) — both
  /// states mean the sync layer is finished with its first init pass.
  void _maybeRunOrphanMediaReconcile(
    AsyncValue<ffi.PrismSyncHandle?>? previous,
    AsyncValue<ffi.PrismSyncHandle?> next,
  ) {
    if (_ranOrphanMediaReconcile) return;
    if (next is AsyncLoading) return;
    _ranOrphanMediaReconcile = true;
    unawaited(
      runOrphanMediaReconcileFromRef(ref).catchError((Object e) {
        // runOrphanMediaReconcileFromRef already swallows + logs internally;
        // this catchError is a final safety net so a programmer bug in the
        // reconcile path can never crash app startup.
        debugPrint('Orphan media reconcile threw out (non-fatal): $e');
        return 0;
      }),
    );
  }

  /// Run the bio-media orphan sweep exactly once per app launch, after
  /// `prismSyncHandleProvider` has resolved (so we don't race the sync layer
  /// materializing inbound bio-media). Catches orphaned bio `media_attachments`
  /// rows missed by the on-save hook in add_edit_member_sheet.dart.
  void _maybeRunBioMediaReconcile(
    AsyncValue<ffi.PrismSyncHandle?>? previous,
    AsyncValue<ffi.PrismSyncHandle?> next,
  ) {
    if (_ranBioMediaReconcile) return;
    if (next is AsyncLoading) return;
    _ranBioMediaReconcile = true;
    unawaited(
      runBioMediaReconcileFromRef(ref).catchError((Object e) {
        // runBioMediaReconcileFromRef already swallows + logs internally;
        // this catchError is a final safety net so a programmer bug in the
        // reconcile path can never crash app startup.
        debugPrint('Bio media reconcile threw out (non-fatal): $e');
        return 0;
      }),
    );
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    super.dispose();
  }

  void _onResume() {
    _repairPrimaryDatabaseKeySlot();
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) return;

    // Re-establish the WebSocket if it dropped while backgrounded,
    // resetting the exponential backoff for an immediate reconnect.
    ffi.reconnectWebsocket(handle: handle).catchError((e) {
      debugPrint('WebSocket reconnect on resume failed (non-fatal): $e');
    });

    // Only nudge the sync engine when it's actually configured. Calling
    // onResume before pairing / unlock produces `sync not configured` error
    // spam that's not actionable. `reconnecting` is a transient sibling of
    // `healthy` (credentials + relay config intact), so we nudge in both.
    final health = ref.read(syncHealthProvider);
    if (health == SyncHealthState.healthy ||
        health == SyncHealthState.reconnecting) {
      unawaited(_nudgeSyncOnResume(handle));
    }
  }

  /// Nudge the sync engine on resume, self-healing a failed `onResume`.
  ///
  /// A failed `onResume` must NEVER drop to the destructive "Set up sync again"
  /// UI, and must not strand the engine "Relay not configured" (which breaks
  /// every media download → "Image expired"). On failure we surface the real
  /// cause (the engine now captures the masked iOS resume panic), mark a
  /// transient `reconnecting`, re-read `relay_url` + rebuild the relay via
  /// `configureEngine`, and retry once. Credentials + relay config are always
  /// preserved; the auto-sync driver and the next resume keep retrying.
  Future<void> _nudgeSyncOnResume(ffi.PrismSyncHandle handle) {
    return runResumeSyncNudge(
      onResume: () => ffi.onResume(handle: handle),
      configureEngine: () => ffi.configureEngine(handle: handle),
      triggerSync: () => unawaited(triggerSync(handle)),
      takeLastPanic: ffi.takeLastPanic,
      readHealth: () => ref.read(syncHealthProvider),
      setHealth: (state) =>
          ref.read(syncHealthProvider.notifier).setState(state),
    );
  }

  void _repairPrimaryDatabaseKeySlot() {
    String? verifiedStartupKey;
    try {
      verifiedStartupKey = ref.read(verifiedStartupKeyProvider);
    } catch (_) {
      return;
    }
    unawaited(_repairPrimaryDatabaseKeySlotAsync(verifiedStartupKey));
  }

  Future<void> _repairPrimaryDatabaseKeySlotAsync(
    String? verifiedStartupKey,
  ) async {
    try {
      await repairPrimaryDatabaseKeyFromVerifiedMemory(verifiedStartupKey);
    } catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'prism_plurality',
          context: ErrorDescription(
            'repairing primary database key slot from verified memory',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Run the orphan-media reconcile pass once `prismSyncHandleProvider`
    // has finished its first resolve. Picks up `.enc` files stranded by a
    // crash mid-_resetChat / _resetAll (DB rows deleted, OS killed the
    // process before the file-loop completed). Startup-only sweep.
    ref.listen(prismSyncHandleProvider, _maybeRunOrphanMediaReconcile);
    // Cover the case where the provider was already resolved before this
    // build ran — the listener above won't fire for a cached value, so we
    // peek at the current state and trigger directly.
    _maybeRunOrphanMediaReconcile(null, ref.read(prismSyncHandleProvider));

    // Run the bio-media orphan sweep once per launch, after the sync layer
    // has finished its first init pass (same timing rationale as above).
    ref.listen(prismSyncHandleProvider, _maybeRunBioMediaReconcile);
    _maybeRunBioMediaReconcile(null, ref.read(prismSyncHandleProvider));

    // Keep the FFI event stream alive for the lifetime of the app.
    ref.listen(syncEventStreamProvider, (_, _) {});
    // Keep the diagnostic event buffer alive for the lifetime of the app.
    ref.listen(syncEventLogProvider, (previous, next) {});
    // Keep the PluralKit sync log notifier subscribed so events emitted
    // before the user opens the PK debug screen are still recorded.
    ref.listen(pkSyncEventLogProvider, (_, _) {});
    // Keep the reminder scheduler alive — reschedules on reminder/front changes.
    ref.listen(reminderSchedulerListenerProvider, (previous, next) {});
    // Keep the habit notification listener alive — reschedules on habit changes.
    ref.listen(habitNotificationListenerProvider, (_, _) {});
    // Keep the fronting reminder listener alive — schedules/cancels based on settings.
    ref.listen(frontingReminderListenerProvider, (_, _) {});
    // Keep frontingMigrationModeProvider always-warm. The sync apply path
    // reads `frontingMigrationWritesBlockedProvider` per row inside a
    // `db.transaction(...)` (drift_sync_adapter.dart `_frontingSessionsEntity`
    // → `applyGate`). That read traverses
    // `frontingMigrationWritesBlockedProvider` →
    // `frontingMigrationGateProvider` → `frontingMigrationModeProvider`, and
    // the last one is a StreamProvider whose build callback synchronously
    // calls `systemSettingsDao.watchSettings()`. If the chain is cold when
    // the apply transaction reads it, that Drift call fires from INSIDE the
    // open transaction and deadlocks Drift's commit-result message on the
    // background isolate (verified 2026-05-03 on Pixel 6 Pro fresh-install
    // pairing). Building it here guarantees the chain is warm before any
    // sync apply runs. Do not remove without re-testing fresh-install pairing.
    ref.listen(frontingMigrationModeProvider, (_, _) {});
    // Run the one-time open-session repair once per device, after sync is
    // configured + healthy and the fronting migration is complete. Collapses
    // duplicate open sessions and merges overlapping same-member rows through
    // the sync layer so peers converge. Idempotent; no-ops on later launches.
    ref.listen(frontingOpenSessionRepairBootstrapProvider, (_, _) {});
    // Trigger the SP boards backfill once on first launch after v15 upgrade.
    // The provider is gated on spBoardsBackfilledAt == null and is a no-op on
    // all subsequent launches. Fire-and-forget — errors are non-fatal.
    ref.listen(spBoardsBackfillProvider, (_, _) {});
    // Repair legacy SP-imported replies whose quote snapshot was missing.
    // Candidate-gated; later launches no-op after affected rows are fixed.
    ref.listen(spReplyQuoteBackfillProvider, (_, _) {});
    // Keep the screen-privacy controller warm so the Settings → Privacy
    // & Security toggle is mirrored to the platform secure-display flag
    // for the lifetime of the app.
    ref.listen(screenPrivacyControllerProvider, (_, _) {});

    final router = ref.watch(routerProvider);
    var brightness = ref.watch(themeBrightnessProvider);
    var style = ref.watch(effectiveThemeStyleProvider);
    var cornerStyle = ref.watch(cornerStyleProvider);

    // Resolve the user's accent color and font settings from narrow providers.
    var accentHex = ref.watch(accentColorHexProvider);
    final paletteSource = ref.watch(paletteSourceProvider);
    final paletteSeedColorHex = ref.watch(paletteSeedColorHexProvider);
    final paletteMood = ref.watch(paletteMoodProvider);
    final paletteContrast = ref.watch(paletteContrastProvider);
    final onboardingAppearance = ref.watch(
      onboardingProvider.select(
        (state) => (
          active: state.hasAppearancePreview,
          accentColorHex: state.hasAccentColorPreview
              ? state.accentColorHex
              : null,
          brightness: state.hasThemeBrightnessPreview
              ? state.themeBrightness
              : null,
          style: state.hasThemeStylePreview ? state.themeStyle : null,
          cornerStyle: state.hasCornerStylePreview ? state.cornerStyle : null,
        ),
      ),
    );
    if (onboardingAppearance.active) {
      accentHex = onboardingAppearance.accentColorHex ?? accentHex;
      brightness = onboardingAppearance.brightness ?? brightness;
      final draftStyle = onboardingAppearance.style;
      if (draftStyle != null) {
        style = effectiveThemeStyleForPlatform(
          draftStyle,
          ref.watch(targetPlatformProvider),
        );
      }
      final draftCornerStyle = onboardingAppearance.cornerStyle;
      if (draftCornerStyle != null) {
        cornerStyle = ui_shapes.CornerStyle.values[draftCornerStyle.index];
      }
    }
    final accentColor = accentHex != null
        ? AppColors.fromHex(accentHex)
        : AppColors.prismPurple;

    final fontFamily = ref.watch(fontFamilySettingProvider);
    final useDisplayFont = ref.watch(displayFontInAppBarProvider);
    final rawFontScale = ref.watch(fontScaleSettingProvider);
    final appFontFamily = fontFamily.assetFontFamily;
    final fontScale = rawFontScale < fontFamily.minimumScale
        ? fontFamily.minimumScale
        : rawFontScale;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ThemeData lightTheme;
        ThemeData darkTheme;

        switch (style) {
          case ThemeStyle.materialYou:
            lightTheme = AppTheme.materialYouLight(
              lightDynamic,
              cornerStyle: cornerStyle,
              paletteSource: paletteSource,
              paletteSeedColorHex: paletteSeedColorHex,
              paletteMood: paletteMood,
              paletteContrast: paletteContrast,
            );
            darkTheme = AppTheme.materialYouDark(
              darkDynamic,
              cornerStyle: cornerStyle,
              paletteSource: paletteSource,
              paletteSeedColorHex: paletteSeedColorHex,
              paletteMood: paletteMood,
              paletteContrast: paletteContrast,
            );
          case ThemeStyle.oled:
            lightTheme = AppTheme.light(
              accentColor: accentColor,
              cornerStyle: cornerStyle,
            );
            darkTheme = AppTheme.oled(
              accentColor: accentColor,
              cornerStyle: cornerStyle,
            );
          case ThemeStyle.standard:
            lightTheme = AppTheme.light(
              accentColor: accentColor,
              cornerStyle: cornerStyle,
            );
            darkTheme = AppTheme.dark(
              accentColor: accentColor,
              cornerStyle: cornerStyle,
            );
        }

        // Strip Unbounded from display/headline roles when the user opts out.
        if (!useDisplayFont) {
          lightTheme = AppTheme.withoutDisplayFont(lightTheme);
          darkTheme = AppTheme.withoutDisplayFont(darkTheme);
        }

        // Run after display font stripping so the selected family wins.
        if (appFontFamily != null) {
          lightTheme = lightTheme.copyWith(
            textTheme: lightTheme.textTheme.apply(fontFamily: appFontFamily),
          );
          darkTheme = darkTheme.copyWith(
            textTheme: darkTheme.textTheme.apply(fontFamily: appFontFamily),
          );
        }

        return MaterialApp.router(
          title: 'Prism',
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('es')],
          locale: ref.watch(localeOverrideProvider),
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: switch (brightness) {
            ThemeBrightness.system => ThemeMode.system,
            ThemeBrightness.light => ThemeMode.light,
            ThemeBrightness.dark => ThemeMode.dark,
          },
          routerConfig: router,
          builder: (context, child) {
            Widget result = child ?? const SizedBox.shrink();
            if (fontScale != 1.0) {
              result = MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(fontScale)),
                child: result,
              );
            }
            return PrismKeyboardDismissScope(
              child: PrismToastHost(child: result),
            );
          },
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
