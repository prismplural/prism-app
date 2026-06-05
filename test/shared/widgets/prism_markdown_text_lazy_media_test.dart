import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
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
}
