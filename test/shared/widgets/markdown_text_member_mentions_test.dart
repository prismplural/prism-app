import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';

void main() {
  const aliceId = '11111111-2222-3333-4444-555555555555';
  const ghostId = 'abcdef12-3456-7890-abcd-ef1234567890';
  final alice = Member(id: aliceId, name: 'Alice', createdAt: DateTime(2026));

  testWidgets('renders member mention tokens as display names', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownText(
            data: 'Hi @[$aliceId] and @[$ghostId]',
            memberMap: {alice.id: alice},
          ),
        ),
      ),
    );

    expect(find.textContaining('@Alice'), findsOneWidget);
    expect(find.textContaining('@Unknown'), findsOneWidget);
    expect(find.textContaining('@[$aliceId]'), findsNothing);
    expect(find.textContaining('@[$ghostId]'), findsNothing);
  });

  testWidgets('keeps tappable member mentions inline with surrounding text', (
    tester,
  ) async {
    String? tappedMemberId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownText(
            data: 'hello @[$aliceId]',
            memberMap: {alice.id: alice},
            onTapMember: (id) => tappedMemberId = id,
          ),
        ),
      ),
    );

    expect(find.textContaining('hello @Alice'), findsOneWidget);

    await tester.tap(find.textContaining('hello @Alice'));
    expect(tappedMemberId, aliceId);
  });
}
