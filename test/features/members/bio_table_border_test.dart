import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';

Future<Table> _pumpTable(WidgetTester tester, String data) async {
  await _pumpMarkdown(tester, data);
  return tester.widget<Table>(find.byType(Table));
}

Future<void> _pumpMarkdown(WidgetTester tester, String data) async {
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
}

bool _hasDecoratedBlockquote(WidgetTester tester) {
  return _decoratedBlockquoteCount(tester) > 0;
}

int _decoratedBlockquoteCount(WidgetTester tester) {
  return tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((
    decoratedBox,
  ) {
    final decoration = decoratedBox.decoration;
    return decoration is BoxDecoration &&
        decoration.border is Border &&
        (decoration.border as Border).left.width == 3;
  }).length;
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

    testWidgets(':::#hex renders a table with that border color', (
      tester,
    ) async {
      final table = await _pumpTable(tester, ':::#FF8800\n$rows\n:::');
      expect(table.border, isNotNull);
      expect(table.border!.top.color, const Color(0xFFFF8800));
      expect(table.border!.top.width, greaterThan(0));
    });

    testWidgets('table inside blockquote renders as a table', (tester) async {
      final table = await _pumpTable(
        tester,
        '> | left | right |\n'
        '> | - | - |\n'
        '> | moon | water |',
      );

      expect(table.border, isNotNull);
      expect(table.border!.top.width, greaterThan(0));
      expect(table.children.first.children, hasLength(2));
      expect(_hasDecoratedBlockquote(tester), isTrue);
    });

    testWidgets('partially quoted table is promoted into blockquote', (
      tester,
    ) async {
      final table = await _pumpTable(
        tester,
        '> | left | right |\n'
        '| - | - |\n'
        '| moon | water |',
      );

      expect(table.children.first.children, hasLength(2));
      expect(_hasDecoratedBlockquote(tester), isTrue);
    });

    testWidgets('blockquote marker inside cell stays in table', (tester) async {
      final table = await _pumpTable(
        tester,
        '| left | right |\n'
        '| - | - |\n'
        '| > moon | water |',
      );

      expect(table.children.first.children, hasLength(2));
      expect(table.children, hasLength(2));
    });

    testWidgets('partially quoted SP-style one-column tables stay quoted', (
      tester,
    ) async {
      await _pumpMarkdown(
        tester,
        ' > | [⠀⠀⠀  ⠀ ⠀⠀⠀⠀ (。♡∇♡。) .ᐟ.ᐟ]() |\n'
        '| --- |\n'
        '\n'
        '>> |  [trains]()      [otomes]()       monochrome     '
        'liminal spaces    water     soft textures     |\n'
        '| --- |',
      );

      final tables = tester.widgetList<Table>(find.byType(Table)).toList();
      expect(tables, hasLength(2));
      expect(
        tables.every((table) => table.children.first.children.length == 1),
        isTrue,
      );
      expect(_decoratedBlockquoteCount(tester), greaterThanOrEqualTo(2));
    });

    testWidgets('styled segment applies to partially quoted table', (
      tester,
    ) async {
      final table = await _pumpTable(
        tester,
        ':::plain\n'
        '> | left | right |\n'
        '| - | - |\n'
        '| moon | water |\n'
        ':::',
      );

      final border = table.border;
      expect(border == null || border.top.width == 0, isTrue);
      expect(border == null || border.verticalInside.width == 0, isTrue);
      expect(_hasDecoratedBlockquote(tester), isTrue);
    });
  });
}
