import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/widgets/mention_overlay.dart';

void main() {
  testWidgets('mention overlay surface follows the active color scheme', (
    tester,
  ) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF006C60),
        brightness: Brightness.light,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: MentionOverlay(
              members: [
                Member(id: 'lyra', name: 'Lyra', createdAt: DateTime(2026)),
              ],
              filter: 'lyr',
              availableWidth: 320,
              onSelect: (_) {},
              onBroadcastSelect: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surfaceFinder = find.descendant(
      of: find.byKey(const Key('mentionOverlaySurface')),
      matching: find.byWidgetPredicate((widget) {
        final decoration = widget is Container ? widget.decoration : null;
        final constraints = widget is Container ? widget.constraints : null;
        return decoration is BoxDecoration &&
            constraints?.maxHeight == 240 &&
            decoration.border != null &&
            decoration.boxShadow != null;
      }),
    );

    expect(surfaceFinder, findsOneWidget);

    final surface = tester.widget<Container>(surfaceFinder);
    final decoration = surface.decoration! as BoxDecoration;
    final border = decoration.border! as Border;

    expect(decoration.color, theme.colorScheme.surface.withValues(alpha: 0.96));
    expect(
      border.top.color,
      theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
    expect(
      decoration.boxShadow?.single.color,
      theme.colorScheme.shadow.withValues(alpha: 0.18),
    );
  });
}
