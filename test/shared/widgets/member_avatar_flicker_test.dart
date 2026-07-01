import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/providers/member_avatar_image_provider.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/group_member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

// Regression coverage for the home-view avatar flicker during PluralKit sync.
//
// The bug: PK sync rewrites the `members.avatar_image_data` blob even when
// the bytes haven't actually changed. Drift's `watchActiveMembers` re-emits
// the row, producing a *new* Uint8List instance for the same content. Flutter's
// MemoryImage uses Uint8List identity for ==, so the new instance fails the
// equality check, the image cache key changes, and an Image widget with the
// default `gaplessPlayback: false` clears its displayed frame while the new
// (synchronous) decode lands. That clear-then-redraw is the visible flicker.
//
// Fix: every member-rendering Image.memory call uses `gaplessPlayback: true`,
// so the previous image stays painted across the ImageProvider swap.

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      terminologySettingProvider.overrideWithValue((
        term: SystemTerminology.headmates,
        customSingular: null,
        customPlural: null,
        useEnglish: false,
      )),
      ...overrides,
    ],
    child: MaterialApp(
      theme: ThemeData.light().copyWith(extensions: [PrismShapes.rounded]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

Uint8List _pngBytes() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
);

void main() {
  group('avatar gaplessPlayback (PK sync flicker regression)', () {
    testWidgets('MemberAvatar Image.memory has gaplessPlayback: true', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MemberAvatar(
            avatarImageData: _pngBytes(),
            memberName: 'Alex',
            size: 64,
          ),
        ),
      );

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(
        images,
        isNotEmpty,
        reason: 'MemberAvatar should render an Image when bytes are provided',
      );
      for (final image in images) {
        expect(
          image.gaplessPlayback,
          isTrue,
          reason:
              'Image.memory in MemberAvatar must use gaplessPlayback: true '
              "so Drift re-emits during PluralKit sync don't flicker the avatar",
        );
      }
    });

    testWidgets('GroupMemberAvatar Image.memory has gaplessPlayback: true', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          GroupMemberAvatar(
            members: [
              GroupAvatarMember(emoji: '🌟', avatarImageData: _pngBytes()),
              GroupAvatarMember(emoji: '🌙', avatarImageData: _pngBytes()),
            ],
            size: 64,
          ),
        ),
      );

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(
        images,
        isNotEmpty,
        reason:
            'GroupMemberAvatar should render Image widgets when bytes are provided',
      );
      for (final image in images) {
        expect(
          image.gaplessPlayback,
          isTrue,
          reason:
              'Image.memory in GroupMemberAvatar must use gaplessPlayback: true '
              "so Drift re-emits during PluralKit sync don't flicker the avatar",
        );
      }
    });

    testWidgets(
      'rebuilding MemberAvatar with a fresh Uint8List of identical content '
      'does not clear the displayed image',
      (tester) async {
        // Two distinct Uint8List instances with byte-identical content —
        // exactly the shape Drift produces when re-emitting a row whose
        // avatar column was rewritten with the same content. The PK sync
        // path that triggers this is `_importMembers` in
        // pluralkit_sync_service.dart, which calls fetchAvatarBytes() and
        // writes the result back even when it equals what's already stored.
        final bytesA = _pngBytes();
        final bytesB = Uint8List.fromList(bytesA);
        expect(
          identical(bytesA, bytesB),
          isFalse,
          reason: 'Test setup: instances must not be identical',
        );
        // Sanity: Uint8List default equality is identity.
        expect(
          bytesA == bytesB,
          isFalse,
          reason:
              'Test setup: Uint8List uses identity equality (this is the '
              'reason MemoryImage cache keys diverge on content-identical bytes)',
        );

        await tester.pumpWidget(
          _wrap(MemberAvatar(avatarImageData: bytesA, size: 64)),
        );
        await tester.pumpAndSettle();

        // Swap to the fresh instance — same content, different identity.
        await tester.pumpWidget(
          _wrap(MemberAvatar(avatarImageData: bytesB, size: 64)),
        );

        // The Image widget must still report gaplessPlayback so its State
        // does NOT call _replaceImage(info: null) on the provider swap.
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.gaplessPlayback, isTrue);
      },
    );

    testWidgets(
      'deferred avatar hydration keeps size stable while bytes arrive',
      (tester) async {
        final streamController = StreamController<Uint8List?>();
        addTearDown(streamController.close);

        await tester.pumpWidget(
          _wrap(
            const MemberAvatar(
              memberId: 'alex',
              memberName: 'Alex',
              emoji: '🌟',
              size: 48,
              deferAvatarLookup: true,
            ),
            overrides: [
              memberAvatarImageDataProvider.overrideWith(
                (ref, memberId) => streamController.stream,
              ),
            ],
          ),
        );

        expect(find.byType(Image), findsNothing);
        final beforeSize = tester.getSize(find.byType(TintedGlassSurface));

        streamController.add(_pngBytes());
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byType(Image), findsOneWidget);
        final afterSize = tester.getSize(find.byType(TintedGlassSurface));
        expect(afterSize, beforeSize);
        expect(afterSize, const Size(48, 48));
        expect(
          tester.widget<Image>(find.byType(Image)).gaplessPlayback,
          isTrue,
        );
      },
    );
  });
}
