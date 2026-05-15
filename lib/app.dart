import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'core/router/app_router.dart';
import 'core/services/notification_providers.dart';
import 'core/services/reminder_scheduler_service.dart';
import 'core/services/screen_privacy_controller.dart';
import 'core/sync/prism_sync_providers.dart';
import 'features/pluralkit/providers/pk_sync_event_log_provider.dart';
import 'features/fronting/migration/providers/fronting_migration_providers.dart';
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

  @override
  void initState() {
    super.initState();
    _appLifecycleListener = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    super.dispose();
  }

  void _onResume() {
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle != null) {
      // Re-establish the WebSocket if it dropped while backgrounded,
      // resetting the exponential backoff for an immediate reconnect.
      ffi.reconnectWebsocket(handle: handle).catchError((e) {
        debugPrint('WebSocket reconnect on resume failed (non-fatal): $e');
      });
      // Only nudge the sync engine when it's actually configured. Calling
      // onResume before pairing / unlock produces `sync not configured`
      // error spam that's not actionable.
      final health = ref.read(syncHealthProvider);
      if (health == SyncHealthState.healthy) {
        ffi.onResume(handle: handle).catchError((e) {
          final structured = PrismSyncStructuredError.tryParse(e);
          debugPrint(
            'onResume failed (non-fatal): ${structured?.userMessage ?? e}',
          );
        });
        // Kick off an explicit sync cycle on resume. `triggerSync` is
        // fire-and-forget and swallows errors so a failed sync doesn't
        // crash the UI — the auto-sync driver will retry in the background.
        // See Appendix B.3 / Bucket 4A of the 2026-04-11 robustness plan.
        triggerSync(handle);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
    // Enforce 1.0x minimum when Open Dyslexic is active.
    final fontScale =
        fontFamily == FontFamily.openDyslexic && rawFontScale < 1.0
        ? 1.0
        : rawFontScale;
    final useOpenDyslexic = fontFamily == FontFamily.openDyslexic;

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

        // Apply Open Dyslexic font family to all text styles if selected.
        // This runs after the display font strip so it overrides everything.
        if (useOpenDyslexic) {
          lightTheme = lightTheme.copyWith(
            textTheme: lightTheme.textTheme.apply(fontFamily: 'OpenDyslexic'),
          );
          darkTheme = darkTheme.copyWith(
            textTheme: darkTheme.textTheme.apply(fontFamily: 'OpenDyslexic'),
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
