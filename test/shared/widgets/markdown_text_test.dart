import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';

void main() {
  testWidgets('task-list checkboxes use Prism dark-mode colors', (
    tester,
  ) async {
    final theme = AppTheme.dark();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: MarkdownText(data: '- [ ] Pending\n- [x] Done'),
        ),
      ),
    );

    final unchecked = tester.widget<Icon>(
      find.byIcon(Icons.check_box_outline_blank),
    );
    final checked = tester.widget<Icon>(find.byIcon(Icons.check_box));

    expect(
      unchecked.color,
      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.92),
    );
    expect(checked.color, theme.colorScheme.primary);
  });
}
