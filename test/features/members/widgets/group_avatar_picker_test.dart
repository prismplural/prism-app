import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/widgets/group_avatar_picker.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

/// A minimal 1×1 gray PNG that is known to decode in the Flutter test environment.
/// (Same fixture used in member_profile_header_test.dart.)
final Uint8List _kOnePxPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lB0Q9wAAAABJRU5ErkJggg==',
);

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('GroupAvatarPicker', () {
    testWidgets('tapping the tile triggers onPickImage callback', (
      tester,
    ) async {
      var pickCount = 0;
      await tester.pumpWidget(
        _wrap(
          GroupAvatarPicker(
            avatarImageData: null,
            emoji: null,
            showEmojiOnAvatar: false,
            onPickImage: () => pickCount++,
            onRemoveImage: () {},
          ),
        ),
      );
      await tester.pump();

      // Tap the InkWell on the avatar tile.
      await tester.tap(find.byType(InkWell).first);
      await tester.pump();

      expect(pickCount, 1);
    });

    testWidgets('remove row is visible when avatarImageData is non-null and non-empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          GroupAvatarPicker(
            avatarImageData: _kOnePxPng,
            emoji: null,
            showEmojiOnAvatar: false,
            onPickImage: () {},
            onRemoveImage: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Remove photo'), findsOneWidget);
    });

    testWidgets('remove row is hidden when avatarImageData is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          GroupAvatarPicker(
            avatarImageData: null,
            emoji: null,
            showEmojiOnAvatar: false,
            onPickImage: () {},
            onRemoveImage: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Remove photo'), findsNothing);
    });

    testWidgets(
      'remove row is hidden when avatarImageData is empty (0 bytes)',
      (tester) async {
        // Regression: _blob decodes "" to Uint8List(0) instead of null.
        await tester.pumpWidget(
          _wrap(
            GroupAvatarPicker(
              avatarImageData: Uint8List(0),
              emoji: null,
              showEmojiOnAvatar: false,
              onPickImage: () {},
              onRemoveImage: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Remove photo'), findsNothing);
      },
    );

    testWidgets('tapping the remove row triggers onRemoveImage callback', (
      tester,
    ) async {
      var removeCount = 0;
      await tester.pumpWidget(
        _wrap(
          GroupAvatarPicker(
            avatarImageData: _kOnePxPng,
            emoji: null,
            showEmojiOnAvatar: false,
            onPickImage: () {},
            onRemoveImage: () => removeCount++,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Remove photo'));
      await tester.pump();

      expect(removeCount, 1);
    });

    testWidgets(
      'emoji badge is visible when avatar set AND emoji set AND showEmojiOnAvatar is true',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            GroupAvatarPicker(
              avatarImageData: _kOnePxPng,
              emoji: '🌟',
              showEmojiOnAvatar: true,
              onPickImage: () {},
              onRemoveImage: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Positioned badge should be in a Stack (regardless of whether the image
        // itself decoded — the badge is structural, not image-dependent).
        expect(find.byType(Stack), findsWidgets);
        expect(find.byType(Positioned), findsWidgets);
      },
    );

    testWidgets('emoji badge is hidden when showEmojiOnAvatar is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          GroupAvatarPicker(
            avatarImageData: _kOnePxPng,
            emoji: '🌟',
            showEmojiOnAvatar: false,
            onPickImage: () {},
            onRemoveImage: () {},
          ),
        ),
      );
      await tester.pump();

      // When showEmojiOnAvatar is false, the badge Positioned widget must not
      // be present in the tile — the emoji should NOT overlay the avatar as a badge.
      // (Image.memory may fall back in test env, but badge layout is not used.)
      expect(find.byType(Positioned), findsNothing);
    });

    testWidgets(
      'emoji renders centered (not as badge) when no avatar present',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            GroupAvatarPicker(
              avatarImageData: null,
              emoji: '🌈',
              showEmojiOnAvatar: true,
              onPickImage: () {},
              onRemoveImage: () {},
            ),
          ),
        );
        await tester.pump();

        // Emoji should render in a centered TintedGlassSurface, not in a Stack badge.
        expect(find.text('🌈'), findsOneWidget);
        // There should be no Positioned widget (no badge layout) at the top level.
        expect(find.byType(Positioned), findsNothing);
      },
    );

    testWidgets(
      'folder fallback icon visible when no avatar AND no emoji',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            GroupAvatarPicker(
              avatarImageData: null,
              emoji: null,
              showEmojiOnAvatar: false,
              onPickImage: () {},
              onRemoveImage: () {},
            ),
          ),
        );
        await tester.pump();

        // The folder icon should be visible as the fallback.
        expect(find.byType(Icon), findsWidgets);
      },
    );

    testWidgets(
      'folder fallback icon visible when avatarImageData is empty (0 bytes) AND no emoji',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            GroupAvatarPicker(
              avatarImageData: Uint8List(0),
              emoji: null,
              showEmojiOnAvatar: false,
              onPickImage: () {},
              onRemoveImage: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(Icon), findsWidgets);
        expect(find.text('Remove photo'), findsNothing);
      },
    );

    testWidgets(
      'tile has merged Semantics node with button: true and image: true when avatar set',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _wrap(
            GroupAvatarPicker(
              avatarImageData: _kOnePxPng,
              emoji: null,
              showEmojiOnAvatar: false,
              onPickImage: () {},
              onRemoveImage: () {},
            ),
          ),
        );
        await tester.pump();

        final semantics = tester.getSemantics(
          find.bySemanticsLabel(RegExp('Group photo')),
        );
        expect(semantics.flagsCollection.isButton, isTrue);
        expect(semantics.flagsCollection.isImage, isTrue);
        handle.dispose();
      },
    );

    testWidgets(
      'tile has merged Semantics node with button: true and image: false when no avatar',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _wrap(
            GroupAvatarPicker(
              avatarImageData: null,
              emoji: null,
              showEmojiOnAvatar: false,
              onPickImage: () {},
              onRemoveImage: () {},
            ),
          ),
        );
        await tester.pump();

        final semantics = tester.getSemantics(
          find.bySemanticsLabel(RegExp('Group photo')),
        );
        expect(semantics.flagsCollection.isButton, isTrue);
        expect(semantics.flagsCollection.isImage, isFalse);
        handle.dispose();
      },
    );
  });
}
