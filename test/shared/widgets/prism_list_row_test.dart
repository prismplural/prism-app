import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';

void main() {
  testWidgets('PrismListRow handles taps', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: PrismListRow(
            title: const Text('Row title'),
            subtitle: const Text('Row subtitle'),
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Row title'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
    expect(find.text('Row subtitle'), findsOneWidget);
  });

  testWidgets('PrismSettingsRow renders icon and chevron', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Material(
            child: PrismSettingsRow(
              icon: AppIcons.navSettings,
              title: 'Settings',
              subtitle: 'Manage app behavior',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Manage app behavior'), findsOneWidget);
    expect(find.byIcon(AppIcons.navSettings), findsOneWidget);
    expect(find.byIcon(AppIcons.chevronRightRounded), findsOneWidget);
  });
}
