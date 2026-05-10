import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

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
  });
}
