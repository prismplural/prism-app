import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/views/edit_sleep_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';

void main() {
  testWidgets(
    'Back closes quality popup without dismissing untouched sleep editor',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = FrontingSession(
        id: 'synthetic-sleep',
        startTime: DateTime(2026, 7, 1, 22),
        endTime: DateTime(2026, 7, 2, 7),
        notes: 'Example notes',
        sessionType: SessionType.sleep,
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => EditSleepSheet.show(context, session),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PrismSelect<SleepQuality>));
      await tester.pumpAndSettle();
      expect(find.text('Good'), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Good'), findsNothing);
      expect(find.byType(EditSleepSheet), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(EditSleepSheet), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'open root popup registers Android back handling',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final handlesBack = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
            handlesBack.add(call.arguments as bool);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Center(
                child: BlurPopupAnchor(
                  itemCount: 1,
                  itemBuilder: (_, _, close) => TextButton(
                    onPressed: close,
                    child: const Text('Menu item'),
                  ),
                  child: const Text('Open menu'),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
        ),
      );
      await tester.pumpAndSettle();
      expect(handlesBack.last, isFalse);
      await tester.tap(find.text('Open menu'));
      await tester.pumpAndSettle();
      expect(find.text('Menu item'), findsOneWidget);
      expect(
        handlesBack.last,
        isTrue,
        reason: 'Android must dispatch Back to Flutter while a popup is open.',
      );
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Menu item'), findsNothing);
      expect(find.text('Open menu'), findsOneWidget);
      expect(handlesBack.last, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
