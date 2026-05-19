import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/widgets/group_avatar_picker.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// A minimal 1×1 gray PNG that is known to decode in the Flutter test environment.
/// (Same fixture used in member_profile_header_test.dart.)
final Uint8List _kOnePxPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lB0Q9wAAAABJRU5ErkJggg==',
);

Widget _wrap(Widget child) => ProviderScope(
  overrides: [
    terminologySettingProvider.overrideWithValue((
      term: SystemTerminology.headmates,
      customSingular: null,
      customPlural: null,
      useEnglish: false,
    )),
  ],
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

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();

      expect(pickCount, 1);
    });

    testWidgets('camera badge is always visible', (tester) async {
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

      expect(find.byIcon(AppIcons.cameraAlt), findsOneWidget);
    });

    testWidgets('remove × badge is visible when avatarImageData is non-null and non-empty', (
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

      expect(find.byIcon(AppIcons.close), findsOneWidget);
    });

    testWidgets('remove × badge is hidden when avatarImageData is null', (
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

      expect(find.byIcon(AppIcons.close), findsNothing);
    });

    testWidgets(
      'remove × badge is hidden when avatarImageData is empty (0 bytes)',
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

        expect(find.byIcon(AppIcons.close), findsNothing);
      },
    );

    testWidgets('tapping the remove × badge triggers onRemoveImage callback', (
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

      await tester.tap(find.byIcon(AppIcons.close));
      await tester.pump();

      expect(removeCount, 1);
    });

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
