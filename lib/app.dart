import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'core/router/app_router.dart';
import 'core/services/reminder_scheduler_service.dart';
import 'core/sync/prism_sync_providers.dart';
import 'domain/models/system_settings.dart';
import 'features/settings/providers/settings_providers.dart';
import 'shared/theme/app_colors.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/prism_toast.dart';

/// Remove Unbounded from display/headline text theme roles so the system font
/// is used instead when the user disables the display font setting.
ThemeData _stripDisplayFont(ThemeData theme) {
  final tt = theme.textTheme;
  return theme.copyWith(
    textTheme: tt.copyWith(
      displayLarge: tt.displayLarge?.copyWith(fontFamily: null, letterSpacing: 0),
      displayMedium: tt.displayMedium?.copyWith(fontFamily: null, letterSpacing: 0),
      displaySmall: tt.displaySmall?.copyWith(fontFamily: null, letterSpacing: 0),
      headlineLarge: tt.headlineLarge?.copyWith(fontFamily: null, letterSpacing: 0),
    ),
  );
}

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
      ffi.onResume(handle: handle).catchError((e) {
        // Non-fatal: sync engine may not be configured yet
        debugPrint('onResume failed (non-fatal): $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the FFI event stream alive for the lifetime of the app.
    ref.listen(syncEventStreamProvider, (_, _) {});
    // Keep the diagnostic event buffer alive for the lifetime of the app.
    ref.listen(syncEventLogProvider, (previous, next) {});
    // Keep the reminder scheduler alive — reschedules on reminder/front changes.
    ref.listen(reminderSchedulerListenerProvider, (previous, next) {});

    final router = ref.watch(routerProvider);
    final brightness = ref.watch(themeBrightnessProvider);
    final style = ref.watch(themeStyleProvider);

    // Resolve the user's accent color and font settings from narrow providers.
    final accentHex = ref.watch(accentColorHexProvider);
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
            lightTheme = AppTheme.materialYouLight(lightDynamic);
            darkTheme = AppTheme.materialYouDark(darkDynamic);
          case ThemeStyle.oled:
            lightTheme = AppTheme.light(accentColor: accentColor);
            darkTheme = AppTheme.oled(accentColor: accentColor);
          case ThemeStyle.standard:
            lightTheme = AppTheme.light(accentColor: accentColor);
            darkTheme = AppTheme.dark(accentColor: accentColor);
        }

        // Strip Unbounded from display/headline roles when the user opts out.
        if (!useDisplayFont) {
          lightTheme = _stripDisplayFont(lightTheme);
          darkTheme = _stripDisplayFont(darkTheme);
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
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
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
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(fontScale),
                ),
                child: result,
              );
            }
            return PrismToastHost(child: result);
          },
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
