import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/providers/accessibility_preferences_provider.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/unsaved_changes_guard.dart';

import '../../helpers/fake_repositories.dart';

void main() {
  testWidgets('PrismSheet.show renders title and content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                title: 'Add Member',
                subtitle: 'Create a new member',
                builder: (context) => const Text('Sheet body content'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Add Member'), findsOneWidget);
    expect(find.text('Create a new member'), findsOneWidget);
    expect(find.text('Sheet body content'), findsOneWidget);
  });

  testWidgets('PrismSheet.show renders actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                title: 'Test',
                builder: (context) => const Text('Content'),
                actions: [
                  TextButton(onPressed: () {}, child: const Text('Cancel')),
                  TextButton(onPressed: () {}, child: const Text('Save')),
                ],
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('PrismSheet.show without title renders content only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                builder: (context) => const Text('Plain content'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Plain content'), findsOneWidget);
  });

  testWidgets('PrismSheet title applies single-line ellipsis overflow', (
    tester,
  ) async {
    const longTitle =
        'A very long title that would normally overflow and wrap across '
        'multiple lines inside the compact sheet header area';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                title: longTitle,
                builder: (_) => const Text('Body'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final titleWidget = tester.widget<Text>(find.text(longTitle));
    expect(titleWidget.maxLines, 1);
    expect(titleWidget.overflow, TextOverflow.ellipsis);
  });

  testWidgets('PrismSheet custom drag handle is excluded from semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                builder: (_) => const Text('Content'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // The custom drag handle container is wrapped in ExcludeSemantics so it
    // doesn't appear as an unlabelled interactive region to screen readers.
    expect(find.byType(ExcludeSemantics), findsWidgets);
  });

  testWidgets('PrismSheet.show with maxHeightFactor bounds sheet height', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                maxHeightFactor: 0.5,
                builder: (_) => const Text('Bounded content'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Bounded content'), findsOneWidget);

    // The ConstrainedBox that enforces maxHeightFactor should be present.
    expect(find.byType(ConstrainedBox), findsWidgets);
  });

  testWidgets('PrismSheet.show with minHeightFactor sets minimum height', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                minHeightFactor: 0.3,
                builder: (_) => const Text('Min height content'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Min height content'), findsOneWidget);

    // ConstrainedBox applies the minHeightFactor constraint.
    expect(find.byType(ConstrainedBox), findsWidgets);
  });

  testWidgets('PrismSheet.show without size factors renders at natural size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.show(
                context: context,
                builder: (_) => const Text('Natural size content'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Natural size content'), findsOneWidget);
  });

  testWidgets('PrismSheet.show presents as a side sheet on wide windows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    final appPrefs = FakeAppPreferenceRepository();
    addTearDown(appPrefs.close);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                PrismSheet.show(
                  context: context,
                  title: 'Wide sheet',
                  builder: (_) => const Text('Wide content'),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final contentTopLeft = tester.getTopLeft(find.text('Wide content'));
    final panelFinder = find.byKey(const Key('detailSideSheetPanel'));
    final panelTopLeft = tester.getTopLeft(panelFinder);
    final panelBottomRight = tester.getBottomRight(panelFinder);
    final panelMaterial = tester.widget<Material>(panelFinder);

    expect(find.text('Wide sheet'), findsOneWidget);
    expect(panelFinder, findsOneWidget);
    expect(panelTopLeft.dx, closeTo(468, 1));
    expect(panelTopLeft.dy, closeTo(12, 1));
    expect(panelBottomRight.dx, closeTo(988, 1));
    expect(panelBottomRight.dy, closeTo(688, 1));
    expect(panelMaterial.shape, isA<RoundedRectangleBorder>());
    expect(panelMaterial.clipBehavior, Clip.antiAlias);
    final barrierColors = _modalBarrierColors(tester);
    expect(barrierColors, isNotEmpty);
    expect(barrierColors, everyElement(anyOf(isNull, Colors.transparent)));
    expect(contentTopLeft.dx, greaterThan(480));
    expect(contentTopLeft.dy, lessThan(120));
  });

  testWidgets(
    'PrismSheet.show tints behind side sheets when accessibility dimming is enabled',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 700);
      final appPrefs = FakeAppPreferenceRepository()
        ..seed(dimBackgroundBehindSheetsPreference, true);
      addTearDown(appPrefs.close);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
          ],
          child: MaterialApp(
            home: _AccessibilityPreferenceWarmup(
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    PrismSheet.show(
                      context: context,
                      title: 'Tinted sheet',
                      builder: (_) => const Text('Tinted content'),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final barrierColors = _modalBarrierColors(tester);

      expect(find.byKey(const Key('detailSideSheetPanel')), findsOneWidget);
      expect(find.text('Tinted content'), findsOneWidget);
      expect(barrierColors, isNotEmpty);
      expect(
        barrierColors,
        anyElement(
          isA<Color>().having((color) => color.a, 'alpha', greaterThan(0)),
        ),
      );
    },
  );

  testWidgets(
    'PrismSheet.show uses centered sheets on wide windows when forced',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 700);
      final appPrefs = FakeAppPreferenceRepository()
        ..seed(forceCenteredSheetsPreference, true);
      addTearDown(appPrefs.close);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
          ],
          child: MaterialApp(
            home: _AccessibilityPreferenceWarmup(
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    PrismSheet.show(
                      context: context,
                      title: 'Forced centered sheet',
                      builder: (_) => const Text('Centered content'),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Centered content'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byKey(const Key('detailSideSheetPanel')), findsNothing);
    },
  );

  testWidgets(
    'PrismSheet.showFullScreen presents as a side sheet on wide windows',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 700);
      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ScrollController? suppliedController;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PrismSheet.showFullScreen(
                    context: context,
                    builder: (_, scrollController) {
                      suppliedController = scrollController;
                      return Column(
                        children: [
                          const PrismSheetTopBar(title: 'Wide full sheet'),
                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              children: const [Text('Scrollable row')],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(suppliedController, isNotNull);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(
        tester.getTopLeft(find.text('Wide full sheet')).dx,
        greaterThan(480),
      );
    },
  );

  testWidgets('wide non-dismissible PrismSheet ignores scrim and Escape', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    final appPrefs = FakeAppPreferenceRepository();
    addTearDown(appPrefs.close);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                PrismSheet.show(
                  context: context,
                  isDismissible: false,
                  builder: (_) => const Text('Locked content'),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(100, 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Locked content'), findsOneWidget);
  });

  testWidgets('wide dirty PrismSheet prompts before scrim dismissal', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    final appPrefs = FakeAppPreferenceRepository();
    addTearDown(appPrefs.close);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PrismSheet.show<void>(
                    context: context,
                    builder: (_) => const UnsavedChangesGuard<void>(
                      hasUnsavedChanges: true,
                      child: Text('Dirty side sheet'),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(100, 100));
    await tester.pumpAndSettle();

    expect(find.text('Dirty side sheet'), findsOneWidget);
    expect(find.text('Discard changes?'), findsOneWidget);
  });

  testWidgets('PrismSheet includes bottom navigation inset in padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(viewPadding: EdgeInsets.only(bottom: 48)),
          child: Scaffold(
            body: PrismSheet(title: 'Sheet', child: Text('Body')),
          ),
        ),
      ),
    );

    final sheetPadding = tester.widget<Padding>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Padding &&
                widget.padding is EdgeInsets &&
                (widget.padding as EdgeInsets).top == 16 &&
                (widget.padding as EdgeInsets).bottom == 64,
          )
          .first,
    );

    expect((sheetPadding.padding as EdgeInsets).bottom, 64);
  });

  testWidgets('PrismSheetTopBar close action has a localized semantics label', (
    tester,
  ) async {
    Finder semanticsWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en'), Locale('es')],
          locale: Locale('es'),
          home: Scaffold(body: PrismSheetTopBar(title: 'Test title')),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(semanticsWithLabel('Cerrar'), findsAtLeastNWidgets(1));
  });

  testWidgets('PrismSheetTopBar close action respects PopScope guards', (
    tester,
  ) async {
    var popAttempts = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PrismSheet.showFullScreen<void>(
                    context: context,
                    builder: (context, scrollController) => PopScope(
                      canPop: false,
                      onPopInvokedWithResult: (didPop, result) {
                        if (!didPop) popAttempts++;
                      },
                      child: const Column(
                        children: [
                          PrismSheetTopBar(title: 'Guarded sheet'),
                          Expanded(child: SizedBox.shrink()),
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PrismGlassIconButton).first);
    await tester.pumpAndSettle();

    expect(find.text('Guarded sheet'), findsOneWidget);
    expect(popAttempts, 1);
  });

  testWidgets('UnsavedChangesGuard confirms before closing dirty sheets', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PrismSheet.showFullScreen<void>(
                    context: context,
                    builder: (context, scrollController) =>
                        const UnsavedChangesGuard<void>(
                          hasUnsavedChanges: true,
                          child: Column(
                            children: [
                              PrismSheetTopBar(title: 'Dirty sheet'),
                              Expanded(child: SizedBox.shrink()),
                            ],
                          ),
                        ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PrismGlassIconButton).first);
    await tester.pumpAndSettle();

    expect(find.text('Dirty sheet'), findsOneWidget);
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Dirty sheet'), findsOneWidget);
    expect(find.text('Discard changes?'), findsNothing);

    await tester.tap(find.byType(PrismGlassIconButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Dirty sheet'), findsNothing);
  });

  testWidgets(
    'dirty standard sheets restore before confirming swipe dismissal',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    PrismSheet.show<void>(
                      context: context,
                      builder: (context) => const UnsavedChangesGuard<void>(
                        hasUnsavedChanges: true,
                        child: SizedBox(
                          height: 240,
                          child: Center(child: Text('Dirty standard sheet')),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.drag(
        find.text('Dirty standard sheet'),
        const Offset(0, 280),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dirty standard sheet'), findsOneWidget);
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Dirty standard sheet'), findsOneWidget);
      expect(find.text('Discard changes?'), findsNothing);
    },
  );

  testWidgets(
    'dirty full-screen sheets restore before confirming swipe dismissal',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    PrismSheet.showFullScreen<void>(
                      context: context,
                      builder: (context, scrollController) =>
                          UnsavedChangesGuard<void>(
                            hasUnsavedChanges: true,
                            child: Column(
                              children: [
                                const PrismSheetTopBar(
                                  title: 'Dirty full sheet',
                                ),
                                Expanded(
                                  child: ListView(
                                    controller: scrollController,
                                    children: const [
                                      SizedBox(
                                        height: 900,
                                        child: Center(
                                          child: Text('Swipe content'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.drag(find.text('Swipe content'), const Offset(0, 700));
      await tester.pumpAndSettle();

      expect(find.text('Dirty full sheet'), findsOneWidget);
      expect(find.text('Swipe content'), findsOneWidget);
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Dirty full sheet'), findsOneWidget);
      expect(find.text('Swipe content'), findsOneWidget);
      expect(find.text('Discard changes?'), findsNothing);
    },
  );

  // Regression test for the auto-theme-switch bug: when the system flips
  // light↔dark while a long-lived PrismSheet is open, the sheet's background
  // must follow the new theme. Earlier code passed an explicit backgroundColor
  // to showModalBottomSheet which snapshot the color at open-time and left
  // the sheet stuck on the old theme.
  testWidgets(
    'PrismSheet background tracks theme changes while the sheet is open',
    (tester) async {
      const lightSheetBg = Color(0xFFAABBCC);
      const darkSheetBg = Color(0xFF112233);

      final brightnessNotifier = ValueNotifier<Brightness>(Brightness.light);
      addTearDown(brightnessNotifier.dispose);

      Widget buildApp() {
        return ValueListenableBuilder<Brightness>(
          valueListenable: brightnessNotifier,
          builder: (context, brightness, _) {
            return MaterialApp(
              theme: ThemeData(
                brightness: Brightness.light,
                bottomSheetTheme: const BottomSheetThemeData(
                  backgroundColor: lightSheetBg,
                ),
              ),
              darkTheme: ThemeData(
                brightness: Brightness.dark,
                bottomSheetTheme: const BottomSheetThemeData(
                  backgroundColor: darkSheetBg,
                ),
              ),
              themeMode: brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              home: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    PrismSheet.show(
                      context: context,
                      builder: (_) => const SizedBox(
                        key: Key('sheet-body'),
                        height: 100,
                        child: Text('Body'),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        );
      }

      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      Material findSheetMaterial() {
        return tester.widget<Material>(
          find
              .ancestor(
                of: find.byKey(const Key('sheet-body')),
                matching: find.byType(Material),
              )
              .first,
        );
      }

      expect(findSheetMaterial().color, lightSheetBg);

      // Flip the app to dark mode while the sheet is still on screen.
      brightnessNotifier.value = Brightness.dark;
      await tester.pumpAndSettle();

      expect(
        findSheetMaterial().color,
        darkSheetBg,
        reason:
            'PrismSheet.show must not snapshot bottomSheetTheme.backgroundColor '
            'at open-time — re-introducing an explicit backgroundColor on '
            'showModalBottomSheet leaves the sheet stuck on the old theme '
            'after a system light/dark switch.',
      );
    },
  );

  testWidgets('PrismSheet.showFullScreen background tracks theme changes', (
    tester,
  ) async {
    const lightSheetBg = Color(0xFFAABBCC);
    const darkSheetBg = Color(0xFF112233);

    final brightnessNotifier = ValueNotifier<Brightness>(Brightness.light);
    addTearDown(brightnessNotifier.dispose);

    await tester.pumpWidget(
      ValueListenableBuilder<Brightness>(
        valueListenable: brightnessNotifier,
        builder: (context, brightness, _) {
          return MaterialApp(
            theme: ThemeData(
              brightness: Brightness.light,
              bottomSheetTheme: const BottomSheetThemeData(
                backgroundColor: lightSheetBg,
              ),
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              bottomSheetTheme: const BottomSheetThemeData(
                backgroundColor: darkSheetBg,
              ),
            ),
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PrismSheet.showFullScreen(
                    context: context,
                    builder: (_, _) => const SizedBox(
                      key: Key('full-sheet-body'),
                      height: 100,
                      child: Text('Body'),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          );
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    Material findSheetMaterial() {
      return tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(const Key('full-sheet-body')),
              matching: find.byType(Material),
            )
            .first,
      );
    }

    expect(findSheetMaterial().color, lightSheetBg);

    brightnessNotifier.value = Brightness.dark;
    await tester.pumpAndSettle();

    expect(findSheetMaterial().color, darkSheetBg);
  });

  testWidgets(
    'PrismSheet.showFullScreen shrinks its viewport above the keyboard',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const bodyKey = Key('keyboard-sheet-body');

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                PrismSheet.showFullScreen(
                  context: context,
                  builder: (_, scrollController) => SizedBox.expand(
                    key: bodyKey,
                    child: ListView(
                      controller: scrollController,
                      children: const [TextField()],
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final bodyFinder = find.byKey(bodyKey);
      final bottomBefore = tester.getBottomLeft(bodyFinder).dy;

      // Simulate iOS keyboard appearing. Without the inset-aware wrapper the
      // sheet body still extends to the bottom of the screen, so the focused
      // TextField stays hidden behind the keyboard.
      const keyboardHeight = 300.0;
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboardHeight * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpAndSettle();

      final bottomAfter = tester.getBottomLeft(bodyFinder).dy;

      expect(
        bottomBefore - bottomAfter,
        closeTo(keyboardHeight, 1),
        reason:
            'Sheet body should shrink by the keyboard height so focused '
            'fields can scroll above the keyboard',
      );
    },
  );
}

class _AccessibilityPreferenceWarmup extends ConsumerWidget {
  const _AccessibilityPreferenceWarmup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dimBackgroundBehindSheetsProvider);
    ref.watch(forceCenteredSheetsProvider);
    return child;
  }
}

List<Color?> _modalBarrierColors(WidgetTester tester) {
  return tester
      .widgetList<Widget>(
        find.byWidgetPredicate(
          (widget) => widget is ModalBarrier || widget is AnimatedModalBarrier,
        ),
      )
      .map(
        (barrier) => switch (barrier) {
          ModalBarrier(:final color) => color,
          AnimatedModalBarrier(:final color) => color.value,
          _ => null,
        },
      )
      .toList();
}
