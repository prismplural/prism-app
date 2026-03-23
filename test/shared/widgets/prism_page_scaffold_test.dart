import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

void main() {
  testWidgets('PrismPageScaffold wires top bar and body', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PrismPageScaffold(
          topBar: PrismTopBar(title: 'Home'),
          body: Text('Body content'),
        ),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Body content'), findsOneWidget);
  });
}
