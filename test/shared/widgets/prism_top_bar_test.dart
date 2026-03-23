import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
              trailing: PrismTopBarAction(icon: Icons.add, onPressed: () {}),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
