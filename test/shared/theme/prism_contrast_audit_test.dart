import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

const _minSoftFillContrast = 1.12;
const _minSoftEdgeContrast = 1.18;
const _minAvatarRingContrast = 1.45;
const _minControlContrast = 3.0;

void main() {
  group('Prism contrast audit', () {
    test('classifies accents against both Prism brightness modes', () {
      expect(
        classifyAccentLegibility(const Color(0xFFAF8EE9)),
        AccentLegibility.tooLight,
      );
      expect(
        classifyAccentLegibility(AppColors.prismPurpleLight),
        AccentLegibility.ok,
      );
      expect(classifyAccentLegibility(Colors.white), AccentLegibility.tooLight);
      expect(classifyAccentLegibility(Colors.black), AccentLegibility.tooDark);
      expect(
        classifyAccentLegibility(const Color(0xFF808080)),
        AccentLegibility.tooDesaturated,
      );
    });

    test('themes adjust primary accents to readable rendered colors', () {
      final themes = <String, ThemeData>{
        'light default legacy accent': AppTheme.light(
          accentColor: const Color(0xFFAF8EE9),
        ),
        'dark default legacy accent': AppTheme.dark(
          accentColor: const Color(0xFFAF8EE9),
        ),
        'light too-light custom accent': AppTheme.light(
          accentColor: Colors.white,
        ),
        'dark too-dark custom accent': AppTheme.dark(accentColor: Colors.black),
        'oled too-dark custom accent': AppTheme.oled(accentColor: Colors.black),
      };

      for (final entry in themes.entries) {
        final theme = entry.value;
        final background = theme.scaffoldBackgroundColor;
        _expectContrast(
          '${entry.key} primary on scaffold',
          theme.colorScheme.primary,
          background,
          prismMinimumTextContrast,
        );
        _expectContrast(
          '${entry.key} onPrimary on primary',
          theme.colorScheme.onPrimary,
          theme.colorScheme.primary,
          prismMinimumTextContrast,
        );
        _expectContrast(
          '${entry.key} error on scaffold',
          theme.colorScheme.error,
          background,
          prismMinimumTextContrast,
        );
      }
    });

    for (final entry in <String, ThemeData>{
      'light': AppTheme.light(accentColor: const Color(0xFFAF8EE9)),
      'dark': AppTheme.dark(accentColor: const Color(0xFFAF8EE9)),
    }.entries) {
      testWidgets('${entry.key} mode shared components keep contrast', (
        tester,
      ) async {
        final theme = entry.value;
        final background = theme.scaffoldBackgroundColor;

        await _pumpContrastWidget(
          tester,
          theme,
          const PrismSurface(child: SizedBox(width: 24, height: 24)),
        );
        final surfaceDecoration = _animatedDecoration(tester);
        _expectRenderedContrast(
          '${entry.key} PrismSurface subtle fill',
          surfaceDecoration.color!,
          background,
          _minSoftFillContrast,
        );
        _expectRenderedContrast(
          '${entry.key} PrismSurface subtle border',
          _borderColor(surfaceDecoration),
          background,
          _minSoftEdgeContrast,
        );

        await _pumpContrastWidget(
          tester,
          theme,
          PrismButton(label: 'Subtle', onPressed: () {}),
        );
        final subtleButtonDecoration = _animatedDecoration(tester);
        final subtleButtonFill = _compositeOver(
          subtleButtonDecoration.color!,
          background,
        );
        _expectContrast(
          '${entry.key} PrismButton subtle fill',
          subtleButtonFill,
          background,
          _minSoftFillContrast,
        );
        _expectRenderedContrast(
          '${entry.key} PrismButton subtle border',
          _borderColor(subtleButtonDecoration),
          background,
          _minSoftEdgeContrast,
        );
        final subtleLabel = tester.widget<Text>(find.text('Subtle'));
        _expectContrast(
          '${entry.key} PrismButton subtle label',
          subtleLabel.style!.color!,
          subtleButtonFill,
          prismMinimumTextContrast,
        );

        await _pumpContrastWidget(
          tester,
          theme,
          PrismButton(
            label: 'Filled',
            onPressed: () {},
            tone: PrismButtonTone.filled,
          ),
        );
        final filledButtonDecoration = _animatedDecoration(tester);
        final filledButtonFill = _compositeOver(
          filledButtonDecoration.color!,
          background,
        );
        _expectContrast(
          '${entry.key} PrismButton filled fill',
          filledButtonFill,
          background,
          _minControlContrast,
        );
        final filledLabel = tester.widget<Text>(find.text('Filled'));
        expect(
          filledLabel.style!.color,
          theme.colorScheme.onPrimary,
          reason: '${entry.key} filled button should keep on-primary text',
        );
        _expectContrast(
          '${entry.key} PrismButton filled label',
          filledLabel.style!.color!,
          filledButtonFill,
          prismMinimumTextContrast,
        );

        await _pumpContrastWidget(
          tester,
          theme,
          PrismIconButton(icon: Icons.add, onPressed: () {}),
        );
        final iconButtonDecoration = _animatedDecoration(tester);
        final iconButtonFill = _compositeOver(
          iconButtonDecoration.color!,
          background,
        );
        _expectContrast(
          '${entry.key} PrismIconButton fill',
          iconButtonFill,
          background,
          _minSoftFillContrast,
        );
        final icon = tester.widget<Icon>(find.byIcon(Icons.add));
        final renderedIconColor = _compositeOver(icon.color!, iconButtonFill);
        _expectContrast(
          '${entry.key} PrismIconButton icon',
          renderedIconColor,
          iconButtonFill,
          _minControlContrast,
        );

        await _pumpContrastWidget(
          tester,
          theme,
          const MemberAvatar(emoji: '?', size: 40),
        );
        final avatarDecoration = _containerDecoration(tester);
        _expectRenderedContrast(
          '${entry.key} MemberAvatar default glass fill',
          avatarDecoration.color!,
          background,
          _minSoftFillContrast,
        );
        _expectRenderedContrast(
          '${entry.key} MemberAvatar default accent ring',
          _borderColor(avatarDecoration),
          background,
          _minAvatarRingContrast,
        );
      });
    }

    testWidgets('member avatars correct pathological custom colors', (
      tester,
    ) async {
      final cases = <String, ({ThemeData theme, String customHex})>{
        'light white avatar': (
          theme: AppTheme.light(accentColor: Colors.white),
          customHex: '#FFFFFF',
        ),
        'dark black avatar': (
          theme: AppTheme.dark(accentColor: Colors.black),
          customHex: '#000000',
        ),
      };

      for (final entry in cases.entries) {
        await _pumpContrastWidget(
          tester,
          entry.value.theme,
          MemberAvatar(
            emoji: '?',
            size: 40,
            customColorEnabled: true,
            customColorHex: entry.value.customHex,
          ),
        );

        final background = entry.value.theme.scaffoldBackgroundColor;
        final decoration = _containerDecoration(tester);
        _expectRenderedContrast(
          '${entry.key} glass fill',
          decoration.color!,
          background,
          _minSoftFillContrast,
        );
        _expectRenderedContrast(
          '${entry.key} accent ring',
          _borderColor(decoration),
          background,
          _minAvatarRingContrast,
        );
      }
    });

    testWidgets('PrismChip custom tints keep readable labels', (tester) async {
      final cases = <String, ({ThemeData theme, Color tint})>{
        'light pastel tint': (
          theme: AppTheme.light(accentColor: AppColors.prismPurpleLight),
          tint: const Color(0xFFB9F7FF),
        ),
        'dark near-black tint': (
          theme: AppTheme.dark(accentColor: AppColors.prismPurple),
          tint: const Color(0xFF1E171F),
        ),
      };

      for (final entry in cases.entries) {
        await _pumpContrastWidget(
          tester,
          entry.value.theme,
          PrismChip(
            label: 'Tinted',
            selected: false,
            tintColor: entry.value.tint,
            onTap: null,
          ),
        );

        final chipDecoration = _animatedDecoration(tester);
        final chipFill = _compositeOver(
          chipDecoration.color!,
          entry.value.theme.scaffoldBackgroundColor,
        );
        final labelStyle = find
            .ancestor(
              of: find.text('Tinted'),
              matching: find.byType(AnimatedDefaultTextStyle),
            )
            .evaluate()
            .map(
              (element) => (element.widget as AnimatedDefaultTextStyle).style,
            )
            .firstWhere((style) => style.fontWeight == FontWeight.w500);

        _expectContrast(
          '${entry.key} PrismChip label',
          labelStyle.color!,
          chipFill,
          prismMinimumTextContrast,
        );
      }
    });

    testWidgets('PrismPill custom tints keep readable labels', (tester) async {
      final cases = <String, ({ThemeData theme, Color tint})>{
        'light pastel tint': (
          theme: AppTheme.light(accentColor: AppColors.prismPurpleLight),
          tint: const Color(0xFFFCE96A),
        ),
        'dark near-black tint': (
          theme: AppTheme.dark(accentColor: AppColors.prismPurple),
          tint: const Color(0xFF111827),
        ),
      };

      for (final entry in cases.entries) {
        await _pumpContrastWidget(
          tester,
          entry.value.theme,
          PrismPill(label: 'Tinted', color: entry.value.tint),
        );

        final pillDecoration =
            tester
                    .widget<Container>(
                      find.descendant(
                        of: find.byType(PrismPill),
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        final labelStyle = tester.widget<Text>(find.text('Tinted')).style!;

        _expectContrast(
          '${entry.key} PrismPill label',
          labelStyle.color!,
          pillDecoration.color!,
          prismMinimumTextContrast,
        );
      }
    });
  });
}

Future<void> _pumpContrastWidget(
  WidgetTester tester,
  ThemeData theme,
  Widget child,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme.brightness == Brightness.light ? theme : AppTheme.light(),
        darkTheme: theme.brightness == Brightness.dark
            ? theme
            : AppTheme.dark(),
        themeMode: theme.brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Center(child: child),
        ),
      ),
    ),
  );
}

BoxDecoration _animatedDecoration(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.byType(AnimatedContainer),
  );
  return container.decoration! as BoxDecoration;
}

BoxDecoration _containerDecoration(WidgetTester tester) {
  final matchingAvatarDecorations = tester
      .widgetList<Container>(find.byType(Container))
      .where(_isTightFortyContainer)
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .where((decoration) => decoration.color != null)
      .toList();
  if (matchingAvatarDecorations.isNotEmpty) {
    return matchingAvatarDecorations.first;
  }

  return tester
      .widgetList<Container>(find.byType(Container))
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((decoration) => decoration.color != null);
}

bool _isTightFortyContainer(Container container) {
  final constraints = container.constraints;
  return constraints?.minWidth == 40 &&
      constraints?.maxWidth == 40 &&
      constraints?.minHeight == 40 &&
      constraints?.maxHeight == 40;
}

Color _borderColor(BoxDecoration decoration) {
  final border = decoration.border! as Border;
  return border.top.color;
}

void _expectRenderedContrast(
  String label,
  Color foreground,
  Color background,
  double minRatio,
) {
  _expectContrast(
    label,
    _compositeOver(foreground, background),
    background,
    minRatio,
  );
}

void _expectContrast(
  String label,
  Color foreground,
  Color background,
  double minRatio,
) {
  final ratio = contrastRatio(foreground, background);
  expect(
    ratio,
    greaterThanOrEqualTo(minRatio - 0.01),
    reason:
        '$label contrast ${ratio.toStringAsFixed(2)}:1 is below '
        '${minRatio.toStringAsFixed(2)}:1 '
        '(${_hex(foreground)} on ${_hex(background)})',
  );
}

Color _compositeOver(Color foreground, Color background) {
  return Color.alphaBlend(foreground, background);
}

String _hex(Color color) {
  final value = color.toARGB32();
  return '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
