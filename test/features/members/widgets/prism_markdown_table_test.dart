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
  group('PrismMarkdownTable column widths', () {
    testWidgets('image in left column hugs, text column flexes',
        (tester) async {
      final table = await _pumpTable(
        tester,
        '| pic | name |\n| - | - |\n| ![](sometag) | Alice |',
      );
      expect(table.columnWidths![0], isA<IntrinsicColumnWidth>());
      expect(table.columnWidths![1], isA<FlexColumnWidth>());
    });

    testWidgets('image in right column hugs, text column flexes',
        (tester) async {
      final table = await _pumpTable(
        tester,
        '| name | pic |\n| - | - |\n| Alice | ![](sometag) |',
      );
      expect(table.columnWidths![0], isA<FlexColumnWidth>());
      expect(table.columnWidths![1], isA<IntrinsicColumnWidth>());
    });

    testWidgets('header-only layout table: image col hugs (no body rows)',
        (tester) async {
      // The common image-beside-text shape: content lives in the header row
      // (a row + separator, no body). The image column must still hug.
      final table = await _pumpTable(
        tester,
        '| ![](sometag) | They/them. Caretaker. |\n| - | - |',
      );
      expect(table.columnWidths![0], isA<IntrinsicColumnWidth>());
      expect(table.columnWidths![1], isA<FlexColumnWidth>());
    });

    testWidgets('header-only layout table: image on the right hugs',
        (tester) async {
      final table = await _pumpTable(
        tester,
        '| They/them. Caretaker. | ![](sometag) |\n| - | - |',
      );
      expect(table.columnWidths![0], isA<FlexColumnWidth>());
      expect(table.columnWidths![1], isA<IntrinsicColumnWidth>());
    });

    testWidgets('text-only table → both columns flex', (tester) async {
      final table = await _pumpTable(
        tester,
        '| a | b |\n| - | - |\n| c | d |',
      );
      expect(table.columnWidths![0], isA<FlexColumnWidth>());
      expect(table.columnWidths![1], isA<FlexColumnWidth>());
    });
  });
}
