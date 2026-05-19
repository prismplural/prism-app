import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/group_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

/// A minimal 1×1 gray PNG known to decode in the Flutter test environment.
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

MemberGroup _makeGroup({
  String name = 'Test Group',
  String? emoji,
  String? colorHex,
  Uint8List? avatarImageData,
}) {
  return MemberGroup(
    id: 'group-1',
    name: name,
    emoji: emoji,
    colorHex: colorHex,
    avatarImageData: avatarImageData,
    createdAt: DateTime(2024),
  );
}

void main() {
  group('GroupAvatar', () {
    testWidgets('renders MemberAvatar with the group\'s avatar bytes when set', (
      tester,
    ) async {
      final group = _makeGroup(avatarImageData: _kOnePxPng, emoji: null);
      await tester.pumpWidget(
        _wrap(GroupAvatar(group: group, size: 40, showEmojiOnAvatar: false)),
      );
      await tester.pumpAndSettle();

      final avatar = tester.widget<MemberAvatar>(find.byType(MemberAvatar));
      expect(avatar.avatarImageData, _kOnePxPng);
    });

    testWidgets('renders MemberAvatar with the group\'s emoji when no avatar', (
      tester,
    ) async {
      final group = _makeGroup(emoji: '🌟', avatarImageData: null);
      await tester.pumpWidget(
        _wrap(GroupAvatar(group: group, size: 40)),
      );
      await tester.pump();

      final avatar = tester.widget<MemberAvatar>(find.byType(MemberAvatar));
      expect(avatar.emoji, '🌟');
      expect(avatar.avatarImageData, isNull);
    });

    testWidgets(
      'renders MemberAvatar with default emoji when neither avatar nor emoji set',
      (tester) async {
        final group = _makeGroup(emoji: null, avatarImageData: null);
        await tester.pumpWidget(
          _wrap(GroupAvatar(group: group, size: 40)),
        );
        await tester.pump();

        final avatar = tester.widget<MemberAvatar>(find.byType(MemberAvatar));
        expect(avatar.emoji, '❔');
      },
    );

    testWidgets('passes tintOverride through to MemberAvatar', (tester) async {
      const override = Color(0xFF00FF00);
      final group = _makeGroup(colorHex: '#FF0000');
      await tester.pumpWidget(
        _wrap(
          GroupAvatar(group: group, size: 40, tintOverride: override),
        ),
      );
      await tester.pump();

      final avatar = tester.widget<MemberAvatar>(find.byType(MemberAvatar));
      expect(avatar.tintOverride, override);
    });

    testWidgets(
      'tintOverride wins over group.colorHex — tintOverride forwarded to MemberAvatar',
      (tester) async {
        const override = Color(0xFF123456);
        final group = _makeGroup(colorHex: '#AABBCC');
        await tester.pumpWidget(
          _wrap(
            GroupAvatar(group: group, size: 40, tintOverride: override),
          ),
        );
        await tester.pump();

        final avatar = tester.widget<MemberAvatar>(find.byType(MemberAvatar));
        expect(avatar.tintOverride, override);
        expect(avatar.customColorHex, '#AABBCC');
      },
    );

    testWidgets(
      'emoji badge visible when avatar + emoji + showEmojiOnAvatar=true',
      (tester) async {
        final group = _makeGroup(avatarImageData: _kOnePxPng, emoji: '🌟');
        await tester.pumpWidget(
          _wrap(
            GroupAvatar(group: group, size: 40, showEmojiOnAvatar: true),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Positioned), findsOneWidget);
        // In test env Image.memory fires errorBuilder and MemberAvatar renders
        // the emoji centered; the badge adds a second instance — both are '🌟'.
        expect(find.text('🌟'), findsWidgets);
      },
    );

    testWidgets('emoji badge hidden when showEmojiOnAvatar=false', (
      tester,
    ) async {
      final group = _makeGroup(avatarImageData: _kOnePxPng, emoji: '🌟');
      await tester.pumpWidget(
        _wrap(
          GroupAvatar(group: group, size: 40, showEmojiOnAvatar: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Positioned), findsNothing);
    });

    testWidgets('emoji badge hidden when group has no emoji', (tester) async {
      final group = _makeGroup(avatarImageData: _kOnePxPng, emoji: null);
      await tester.pumpWidget(
        _wrap(
          GroupAvatar(group: group, size: 40, showEmojiOnAvatar: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Positioned), findsNothing);
    });

    testWidgets(
      'treats 0-byte avatar blob as no-avatar — no Positioned badge shown',
      (tester) async {
        // Regression: _blob decodes "" to Uint8List(0) instead of null.
        // GroupAvatar treats empty bytes the same as null (no avatar).
        final group = _makeGroup(
          avatarImageData: Uint8List(0),
          emoji: '🌟',
        );
        await tester.pumpWidget(
          _wrap(
            GroupAvatar(group: group, size: 40, showEmojiOnAvatar: true),
          ),
        );
        await tester.pump();

        expect(find.byType(Positioned), findsNothing);
        final avatar = tester.widget<MemberAvatar>(find.byType(MemberAvatar));
        expect(avatar.avatarImageData!.isEmpty, isTrue);
      },
    );

    testWidgets('memberName is set to group.name for semantics', (
      tester,
    ) async {
      final group = _makeGroup(name: 'My Group');
      await tester.pumpWidget(
        _wrap(GroupAvatar(group: group, size: 40)),
      );
      await tester.pump();

      final avatar = tester.widget<MemberAvatar>(find.byType(MemberAvatar));
      expect(avatar.memberName, 'My Group');
    });
  });
}
