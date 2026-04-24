import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
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

  testWidgets('PrismTopBar keeps actions close to the safe area top', (
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

    expect(actionTop, 36);
  });
}
