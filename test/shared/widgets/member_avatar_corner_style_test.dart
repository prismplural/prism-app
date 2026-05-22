import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/group_member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

Widget _wrap(Widget child, {required PrismShapes shapes}) {
  return ProviderScope(
    overrides: [
      terminologySettingProvider.overrideWithValue((
        term: SystemTerminology.headmates,
        customSingular: null,
        customPlural: null,
        useEnglish: false,
      )),
    ],
    child: MaterialApp(
      theme: ThemeData.light().copyWith(extensions: [shapes]),
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
  group('MemberAvatar corner style', () {
    testWidgets('rounded mode produces BoxShape.circle border decoration', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MemberAvatar(emoji: '🌟', size: 40, showBorder: true),
          shapes: PrismShapes.rounded,
        ),
      );

      // Find the Container that has the border decoration.
      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .toList();
      final borderContainers = containers.where((c) {
        final deco = c.decoration;
        return deco is BoxDecoration && deco.border != null;
      }).toList();

      expect(
        borderContainers,
        isNotEmpty,
        reason: 'Expected a border Container',
      );
      final deco = borderContainers.first.decoration as BoxDecoration;
      expect(
        deco.shape,
        BoxShape.circle,
        reason: 'Rounded mode should use circle',
      );
      expect(
        deco.borderRadius,
        isNull,
        reason: 'Rounded mode should have null borderRadius',
      );
    });

    testWidgets(
      'angular mode produces BoxShape.rectangle + BorderRadius.zero border decoration',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const MemberAvatar(emoji: '🌟', size: 40, showBorder: true),
            shapes: PrismShapes.angular,
          ),
        );

        final containers = tester
            .widgetList<Container>(find.byType(Container))
            .toList();
        final borderContainers = containers.where((c) {
          final deco = c.decoration;
          return deco is BoxDecoration && deco.border != null;
        }).toList();

        expect(
          borderContainers,
          isNotEmpty,
          reason: 'Expected a border Container',
        );
        final deco = borderContainers.first.decoration as BoxDecoration;
        expect(
          deco.shape,
          BoxShape.rectangle,
          reason: 'Angular mode should use rectangle',
        );
        expect(
          deco.borderRadius,
          BorderRadius.zero,
          reason: 'Angular mode should use BorderRadius.zero',
        );
      },
    );

    testWidgets('image avatars do not paint glass highlight over the image', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MemberAvatar(
            avatarImageData: _pngBytes(),
            memberName: 'Alex',
            size: 40,
          ),
          shapes: PrismShapes.rounded,
        ),
      );
      await tester.pump();

      final overpaintingContainers = tester
          .widgetList<Container>(find.byType(Container))
          .where((container) => container.foregroundDecoration != null)
          .toList();

      expect(
        overpaintingContainers,
        isEmpty,
        reason: 'foregroundDecoration paints above child images',
      );
    });

    testWidgets('blank emoji falls back to visible placeholder glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MemberAvatar(emoji: '', size: 40),
          shapes: PrismShapes.rounded,
        ),
      );

      expect(find.text('❔'), findsOneWidget);
    });

    testWidgets('whitespace emoji falls back to visible placeholder glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MemberAvatar(emoji: '   ', size: 40),
          shapes: PrismShapes.rounded,
        ),
      );

      expect(find.text('❔'), findsOneWidget);
    });

    testWidgets('angular mode squares circular tinted glass surfaces', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TintedGlassSurface.circle(size: 40, child: SizedBox.shrink()),
          shapes: PrismShapes.angular,
        ),
      );

      final decorations = tester
          .widgetList<Container>(find.byType(Container))
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .toList();

      expect(decorations, isNotEmpty);
      expect(decorations.first.shape, BoxShape.rectangle);
      expect(decorations.first.borderRadius, BorderRadius.zero);
    });

    testWidgets('group avatars can split tint and ring member colors', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupMemberAvatar(
            members: [
              GroupAvatarMember(
                emoji: '🌟',
                customColorEnabled: true,
                customColorHex: '#16A34A',
              ),
              GroupAvatarMember(
                emoji: '🌙',
                customColorEnabled: true,
                customColorHex: '#2563EB',
              ),
            ],
          ),
          shapes: PrismShapes.rounded,
        ),
      );

      final decorations = tester
          .widgetList<Container>(find.byType(Container))
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.boxShadow != null)
          .toList();

      expect(decorations, isNotEmpty);
      final decoration = decorations.first;
      final expectedTint = contrastAdjustedAccent(
        AppColors.fromHex('#16A34A'),
        prismLightAccentBackground,
      );
      final expectedBorder = contrastAdjustedAccent(
        AppColors.fromHex('#2563EB'),
        prismLightAccentBackground,
      );

      expect(decoration.border, isA<Border>());
      final border = decoration.border! as Border;
      expect(border.top.width, 1);
      expect(
        border.top.color,
        expectedBorder.withValues(
          alpha: PrismTokens.avatarAccentBorderAlphaLight,
        ),
      );
      expect(
        decoration.color,
        Color.alphaBlend(
          expectedTint.withValues(alpha: PrismTokens.avatarTintAlpha),
          ThemeData.light().colorScheme.surfaceContainerHigh.withValues(
            alpha: PrismTokens.tintedFillAlphaLight,
          ),
        ),
      );
    });
  });
}
