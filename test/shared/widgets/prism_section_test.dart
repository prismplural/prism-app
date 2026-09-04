import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';

void main() {
  testWidgets('PrismSection renders title, description, and footer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: PrismSection(
            title: 'System',
            description: 'Shared options',
            footer: Text('Footer text'),
            child: PrismSectionCard(child: Text('Section content')),
          ),
        ),
      ),
    );

    expect(find.text('System'), findsOneWidget);
    expect(find.text('Shared options'), findsOneWidget);
    expect(find.text('Section content'), findsOneWidget);
    expect(find.text('Footer text'), findsOneWidget);
  });

  testWidgets('PrismPill renders icon and label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: PrismPill(label: '3 active', icon: AppIcons.people),
        ),
      ),
    );

    expect(find.text('3 active'), findsOneWidget);
    expect(find.byIcon(AppIcons.people), findsOneWidget);
  });

  testWidgets('PrismPill ellipsizes long labels in constrained layouts', (
    tester,
  ) async {
    const label = 'A very long user-authored custom status label';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 100, child: PrismPill(label: label)),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text(label));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });
}
