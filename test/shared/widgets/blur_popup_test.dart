import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';

void main() {
  testWidgets('BlurPopupAnchor blocks background semantics while open', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en'), Locale('es')],
          locale: const Locale('es'),
          home: Scaffold(
            body: Stack(
              children: [
                Center(
                  child: Semantics(
                    label: 'Background action',
                    button: true,
                    child: ElevatedButton(
                      onPressed: () {},
                      child: const Text('Background action'),
                    ),
                  ),
                ),
                Center(
                  child: BlurPopupAnchor(
                    semanticLabel: 'Open popup',
                    itemCount: 1,
                    itemBuilder: (context, index, close) => Semantics(
                      label: 'Popup item',
                      button: true,
                      child: TextButton(
                        onPressed: close,
                        child: const Text('Popup item'),
                      ),
                    ),
                    child: const Text('Open popup'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open popup'));
      await tester.pumpAndSettle();

      final closeFinder = find.semantics.byLabel('Cerrar');
      final popupItemFinder = find.semantics.byLabel('Popup item');
      final backgroundFinder = find.semantics.byLabel('Background action');

      expect(closeFinder, findsOne);
      expect(
        closeFinder,
        matchesSemantics(label: 'Cerrar', isButton: true, hasTapAction: true),
      );
      expect(popupItemFinder, findsAtLeastNWidgets(1));
      expect(backgroundFinder, findsNothing);
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
    'BlurPopupAnchor excludes keyboard inset when choosing direction',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(() {
        tester.view.resetViewInsets();
        return tester.binding.setSurfaceSize(null);
      });

      const anchorKey = Key('keyboard-aware-anchor');

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en'), Locale('es')],
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 340,
                  left: 160,
                  child: BlurPopupAnchor(
                    width: 180,
                    maxHeight: 260,
                    itemCount: 6,
                    itemBuilder: (context, index, close) => SizedBox(
                      height: 44,
                      child: Center(child: Text('Menu $index')),
                    ),
                    child: const SizedBox(
                      key: anchorKey,
                      width: 80,
                      height: 40,
                      child: Center(child: Text('Anchor')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Anchor'));
      await tester.pumpAndSettle();

      final anchorTop = tester.getTopLeft(find.byKey(anchorKey)).dy;
      final firstMenuTop = tester.getTopLeft(find.text('Menu 0')).dy;

      expect(firstMenuTop, lessThan(anchorTop));
    },
  );

  testWidgets('BlurPopupAnchor dismisses before route pop on system back', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en'), Locale('es')],
        home: Scaffold(
          body: Center(
            child: BlurPopupAnchor(
              itemCount: 1,
              itemBuilder: (context, index, close) =>
                  TextButton(onPressed: close, child: const Text('Popup item')),
              child: const Text('Anchor'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Anchor'));
    await tester.pumpAndSettle();

    expect(find.text('Popup item'), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.text('Popup item'), findsNothing);
    expect(find.text('Anchor'), findsOneWidget);
  });

  testWidgets('BlurPopupAnchor dismisses when GoRouter pushes another view', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: BlurPopupAnchor(
                itemCount: 1,
                itemBuilder: (context, index, close) => TextButton(
                  onPressed: close,
                  child: const Text('Popup item'),
                ),
                child: const Text('Anchor'),
              ),
            ),
          ),
          routes: [
            GoRoute(
              path: 'detail',
              builder: (context, state) =>
                  const Scaffold(body: Text('Detail view')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en'), Locale('es')],
        routerConfig: router,
      ),
    );

    await tester.tap(find.text('Anchor'));
    await tester.pumpAndSettle();

    expect(find.text('Popup item'), findsOneWidget);

    unawaited(router.push('/detail'));
    await tester.pumpAndSettle();

    expect(find.text('Detail view'), findsOneWidget);
    expect(find.text('Popup item'), findsNothing);
  });

  testWidgets(
    'BlurPopupAnchor removes overlay when disposed during animated close',
    (tester) async {
      var showAnchor = true;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en'), Locale('es')],
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Center(
                  child: showAnchor
                      ? BlurPopupAnchor(
                          itemCount: 1,
                          itemBuilder: (context, index, close) => TextButton(
                            onPressed: () {
                              close();
                              setState(() => showAnchor = false);
                            },
                            child: const Text('Popup item'),
                          ),
                          child: const Text('Anchor'),
                        )
                      : const Text('Anchor removed'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Anchor'));
      await tester.pumpAndSettle();
      expect(find.text('Popup item'), findsOneWidget);

      await tester.tap(find.text('Popup item'));
      await tester.pumpAndSettle();

      expect(find.text('Anchor removed'), findsOneWidget);
      expect(find.text('Popup item'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
