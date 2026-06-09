import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/widgets/list_detail_layout.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';

void main() {
  testWidgets('plain bio text does not subscribe to image providers', (
    tester,
  ) async {
    var imageLibraryBuilds = 0;
    var bioMediaBuilds = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageLibraryProvider.overrideWith((ref) {
            imageLibraryBuilds++;
            return Stream.value(const <MediaAttachment>[]);
          }),
          bioMediaForMemberProvider.overrideWith((ref, memberId) {
            bioMediaBuilds++;
            return Stream.value(const <MediaAttachment>[]);
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PrismMarkdownText(
              data: 'Plain profile text with **markdown**, but no images.',
              memberId: 'member-1',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(imageLibraryBuilds, isZero);
    expect(bioMediaBuilds, isZero);
  });

  testWidgets('bio image references still subscribe to image providers', (
    tester,
  ) async {
    var imageLibraryBuilds = 0;
    var bioMediaBuilds = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageLibraryProvider.overrideWith((ref) {
            imageLibraryBuilds++;
            return Stream.value(const <MediaAttachment>[]);
          }),
          bioMediaForMemberProvider.overrideWith((ref, memberId) {
            bioMediaBuilds++;
            return Stream.value(const <MediaAttachment>[]);
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PrismMarkdownText(
              data: 'A local image: ![flag](comfort-flag)',
              memberId: 'member-1',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(imageLibraryBuilds, greaterThan(0));
    expect(bioMediaBuilds, greaterThan(0));
  });

  testWidgets(
    'member mentions select an available detail pane before routing',
    (tester) async {
      const aliceId = '11111111-2222-3333-4444-555555555555';
      final alice = Member(
        id: aliceId,
        name: 'Alice',
        createdAt: DateTime(2026),
      );
      String? selectedMemberId;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMemberListProvider.overrideWithValue(
              AsyncValue.data([alice]),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListDetailPaneControls(
                clearSelection: null,
                selectDetail: (id) => selectedMemberId = id,
                child: const PrismMarkdownText(data: 'hello @[$aliceId]'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.textContaining('@Alice'));
      await tester.pump();

      expect(selectedMemberId, aliceId);
    },
  );

  testWidgets('non-interactive mentions still render without selecting pane', (
    tester,
  ) async {
    const aliceId = '11111111-2222-3333-4444-555555555555';
    final alice = Member(id: aliceId, name: 'Alice', createdAt: DateTime(2026));
    String? selectedMemberId;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeMemberListProvider.overrideWithValue(AsyncValue.data([alice])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListDetailPaneControls(
              clearSelection: null,
              selectDetail: (id) => selectedMemberId = id,
              child: const PrismMarkdownText(
                data: 'preview @[$aliceId]',
                mentionsInteractive: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('@Alice'), findsOneWidget);

    await tester.tap(find.textContaining('@Alice'));
    await tester.pump();

    expect(selectedMemberId, isNull);
  });

  testWidgets('non-interactive table mentions do not select pane', (
    tester,
  ) async {
    const aliceId = '11111111-2222-3333-4444-555555555555';
    final alice = Member(id: aliceId, name: 'Alice', createdAt: DateTime(2026));
    String? selectedMemberId;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeMemberListProvider.overrideWithValue(AsyncValue.data([alice])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListDetailPaneControls(
              clearSelection: null,
              selectDetail: (id) => selectedMemberId = id,
              child: const PrismMarkdownText(
                data: '| Mention |\n| --- |\n| @[$aliceId] |',
                mentionsInteractive: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('@Alice'), findsOneWidget);

    await tester.tap(find.textContaining('@Alice'));
    await tester.pump();

    expect(selectedMemberId, isNull);
  });
}
