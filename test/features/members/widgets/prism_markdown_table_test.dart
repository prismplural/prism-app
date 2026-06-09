import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/markdown/spoiler_syntax.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';

Future<Table> _pumpTable(
  WidgetTester tester,
  String data, {
  List<Member> members = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        imageLibraryProvider.overrideWith(
          (ref) => Stream<List<MediaAttachment>>.value(const []),
        ),
        activeMemberListProvider.overrideWithValue(AsyncValue.data(members)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 500, child: PrismMarkdownText(data: data)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<Table>(find.byType(Table));
}

void main() {
  group('PrismMarkdownTable column widths', () {
    testWidgets('image in left column hugs, text column flexes', (
      tester,
    ) async {
      final table = await _pumpTable(
        tester,
        '| pic | name |\n| - | - |\n| ![](sometag) | Alice |',
      );
      expect(table.columnWidths![0], isA<IntrinsicColumnWidth>());
      expect(table.columnWidths![1], isA<FlexColumnWidth>());
    });

    testWidgets('image in right column hugs, text column flexes', (
      tester,
    ) async {
      final table = await _pumpTable(
        tester,
        '| name | pic |\n| - | - |\n| Alice | ![](sometag) |',
      );
      expect(table.columnWidths![0], isA<FlexColumnWidth>());
      expect(table.columnWidths![1], isA<IntrinsicColumnWidth>());
    });

    testWidgets('header-only layout table: image col hugs (no body rows)', (
      tester,
    ) async {
      // The common image-beside-text shape: content lives in the header row
      // (a row + separator, no body). The image column must still hug.
      final table = await _pumpTable(
        tester,
        '| ![](sometag) | They/them. Caretaker. |\n| - | - |',
      );
      expect(table.columnWidths![0], isA<IntrinsicColumnWidth>());
      expect(table.columnWidths![1], isA<FlexColumnWidth>());
    });

    testWidgets('header-only layout table: image on the right hugs', (
      tester,
    ) async {
      final table = await _pumpTable(
        tester,
        '| They/them. Caretaker. | ![](sometag) |\n| - | - |',
      );
      expect(table.columnWidths![0], isA<FlexColumnWidth>());
      expect(table.columnWidths![1], isA<IntrinsicColumnWidth>());
    });

    testWidgets('text-only table → both columns flex', (tester) async {
      final table = await _pumpTable(tester, '| a | b |\n| - | - |\n| c | d |');
      expect(table.columnWidths![0], isA<FlexColumnWidth>());
      expect(table.columnWidths![1], isA<FlexColumnWidth>());
    });

    testWidgets('spoilers inside a one-column table render as spoiler pills', (
      tester,
    ) async {
      final table = await _pumpTable(
        tester,
        '| Project Alpha |\n'
        '| --- |\n'
        '| Status: ||internal draft|| |\n'
        '| Notes: ready for review |',
      );

      expect(table.columnWidths, hasLength(1));
      expect(find.byType(SpoilerPill), findsOneWidget);
      final pill = tester.widget<SpoilerPill>(find.byType(SpoilerPill));
      expect(pill.text, 'internal draft');
    });

    testWidgets('member mentions inside table cells resolve to display names', (
      tester,
    ) async {
      const aliceId = '11111111-2222-3333-4444-555555555555';
      final alice = Member(
        id: aliceId,
        name: 'Alice',
        createdAt: DateTime(2026),
      );

      final table = await _pumpTable(
        tester,
        '| Owner | Notes |\n'
        '| --- | --- |\n'
        '| @[$aliceId] | paired with @[$aliceId] |',
        members: [alice],
      );

      expect(table.children, hasLength(2));
      expect(find.textContaining('@Alice'), findsWidgets);
      expect(find.textContaining('@[$aliceId]'), findsNothing);
    });
  });
}
