import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/embedded_pane_marker.dart';
import 'package:prism_plurality/shared/widgets/list_detail_layout.dart';
import 'package:prism_plurality/shared/widgets/modal_side_sheet_marker.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

void main() {
  testWidgets('PrismTopBar renders title and subtitle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: PrismTopBar(title: 'Chat', subtitle: 'All Members'),
        ),
      ),
    );

    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('All Members'), findsOneWidget);
  });

  testWidgets('PrismTopBarAction renders an icon button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            appBar: PrismTopBar(
              title: 'Settings',
              trailing: PrismTopBarAction(
                icon: AppIcons.add,
                tooltip: 'Add',
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(AppIcons.add), findsOneWidget);
  });

  testWidgets('PrismTopBar auto leading uses back outside side sheets', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: Scaffold(
            appBar: PrismTopBar(title: 'Detail', showBackButton: true),
          ),
        ),
      ),
    );

    expect(find.byIcon(AppIcons.arrowBack), findsOneWidget);
    expect(find.byIcon(AppIcons.close), findsNothing);
  });

  testWidgets('PrismTopBar auto leading uses close inside side sheets', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: ModalSideSheetMarker(
            child: Scaffold(
              appBar: PrismTopBar(title: 'Detail', showBackButton: true),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(AppIcons.close), findsOneWidget);
    expect(find.byIcon(AppIcons.arrowBack), findsNothing);
  });

  testWidgets('PrismTopBar auto leading clears embedded detail panes', (
    tester,
  ) async {
    var clearCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: ListDetailPaneControls(
            clearSelection: () => clearCount++,
            selectDetail: (_) {},
            child: const EmbeddedPaneMarker(
              child: Scaffold(appBar: PrismTopBar(title: 'Detail')),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(AppIcons.close), findsOneWidget);
    expect(find.byIcon(AppIcons.arrowBack), findsNothing);

    await tester.tap(find.byIcon(AppIcons.close));
    expect(clearCount, 1);
  });

  testWidgets('PrismTopBar pads actions below the safe area top', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(top: 30),
          viewPadding: EdgeInsets.only(top: 30),
        ),
        child: ProviderScope(
          child: MaterialApp(
            home: PrismPageScaffold(
              topBar: PrismTopBar(
                title: 'Settings',
                trailing: PrismTopBarAction(
                  icon: AppIcons.add,
                  tooltip: 'Add',
                  onPressed: null,
                ),
              ),
              body: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    final actionTop = tester.getTopLeft(find.byType(PrismGlassIconButton)).dy;

    expect(
      actionTop,
      30 + (PrismTokens.topBarHeight - PrismTokens.topBarActionSize) / 2,
    );
  });

  testWidgets('PrismTopBar pads actions without a safe area inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            appBar: PrismTopBar(
              title: 'Settings',
              trailing: PrismTopBarAction(
                icon: AppIcons.add,
                tooltip: 'Add',
                onPressed: null,
              ),
            ),
          ),
        ),
      ),
    );

    final actionTop = tester.getTopLeft(find.byType(PrismGlassIconButton)).dy;

    expect(
      actionTop,
      (PrismTokens.topBarHeight - PrismTokens.topBarActionSize) / 2,
    );
  });
}
