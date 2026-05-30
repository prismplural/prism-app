import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';

Future<Table> _pumpTable(WidgetTester tester, String data) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Avoid DB/repo init — these tables are text-only (no image refs).
        imageLibraryProvider.overrideWith(
          (ref) => Stream<List<MediaAttachment>>.value(const []),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 500, child: PrismMarkdownText(data: data)),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.widget<Table>(find.byType(Table));
}

void main() {
  group('PrismMarkdownText table border control', () {
    const rows = '| a | b |\n| - | - |\n| c | d |';

    testWidgets('default table has a visible border', (tester) async {
      final table = await _pumpTable(tester, rows);
      expect(table.border, isNotNull);
      expect(table.border!.top.width, greaterThan(0));
    });

    testWidgets(':::plain renders a borderless table', (tester) async {
      final table = await _pumpTable(tester, ':::plain\n$rows\n:::');
      // No visible gridlines on any side.
      final b = table.border;
      expect(b == null || b.top.width == 0, isTrue);
      expect(b == null || b.verticalInside.width == 0, isTrue);
    });

    testWidgets(':::#hex renders a table with that border color', (tester) async {
      final table = await _pumpTable(tester, ':::#FF8800\n$rows\n:::');
      expect(table.border, isNotNull);
      expect(table.border!.top.color, const Color(0xFFFF8800));
      expect(table.border!.top.width, greaterThan(0));
    });
  });
}
