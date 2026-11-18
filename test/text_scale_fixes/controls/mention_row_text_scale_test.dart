// Member-mention suggestion rows under text scaling.
//
// Suggestion rows must grow with their text. Pinning the name inside a fixed 48dp
// row (and the broadcast row inside 52dp) cut the glyphs off once the composed
// scale grew, and cut the broadcast row's second line even earlier. The row
// heights below are floors, not limits.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/widgets/mention_overlay.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';
import 'package:prism_plurality/shared/widgets/member_mention_text_field.dart';

import '../../helpers/prism_golden.dart' show loadPrismGoldenFonts;

class _NonLinearTextScaler extends TextScaler {
  const _NonLinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 1.4 : 28.0 + (fontSize - 20) * 3.0;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 3.0;
}

const _scales = <(String, TextScaler)>[
  (
    'system 100% x Prism 50% = 0.5x',
    PrismTextScaler(TextScaler.noScaling, 0.5),
  ),
  ('default text', PrismTextScaler(TextScaler.noScaling, 1.0)),
  ('large text 1.5x', PrismTextScaler(TextScaler.linear(1.5), 1.0)),
  (
    'system 225% x Prism 150% = 3.375x',
    PrismTextScaler(TextScaler.linear(2.25), 1.5),
  ),
  (
    'nonlinear system scaler x Prism 150%',
    PrismTextScaler(_NonLinearTextScaler(), 1.5),
  ),
];

Widget _app(
  Widget home, {
  required TextScaler textScaler,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        fontFamily: 'OpenDyslexic',
        fontFamilyFallback: const ['NotoColorEmoji'],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child ?? const SizedBox.shrink(),
      ),
      home: home,
    ),
  );
}

void _useCompactPhone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026, 1, 1));

void _expectNotVerticallyClamped(
  WidgetTester tester,
  String text,
  String scaleLabel, {
  int maxLines = 1,
}) {
  final finder = find.text(text);
  expect(finder, findsOneWidget, reason: '$scaleLabel: one "$text" label');
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final painter = TextPainter(
    text: TextSpan(
      text: paragraph.text.toPlainText(),
      style: paragraph.text.style,
    ),
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
    maxLines: maxLines,
  )..layout(maxWidth: paragraph.size.width);
  final needed = painter.height;
  painter.dispose();
  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(needed - 0.5),
    reason:
        '$scaleLabel: "$text" needs ${needed.toStringAsFixed(1)}px but its row '
        'gives it ${paragraph.size.height.toStringAsFixed(1)}px, so glyphs are '
        'cut off',
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadPrismGoldenFonts();
  });

  for (final (label, scaler) in _scales) {
    testWidgets('composer suggestion row keeps its name glyphs ($label)', (
      tester,
    ) async {
      _useCompactPhone(tester);
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
      });

      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: MemberMentionTextField(
                  controller: controller,
                  focusNode: focusNode,
                  mentionCandidates: [_member('m1', 'Alexandria')],
                  maxLines: 3,
                ),
              ),
            ),
          ),
          textScaler: scaler,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '$label: no layout error');
      expect(find.text('Alexandria'), findsOneWidget);
      _expectNotVerticallyClamped(tester, 'Alexandria', label);

      // Selecting the suggestion still inserts the atomic mention token.
      await tester.tap(find.text('Alexandria'));
      await tester.pumpAndSettle();
      expect(controller.text, contains('@[m1]'));
    });

    testWidgets('chat overlay member row keeps its name glyphs ($label)', (
      tester,
    ) async {
      _useCompactPhone(tester);
      final selected = <String>[];

      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: MentionOverlay(
                members: [_member('m1', 'Alexandria')],
                filter: 'alex',
                onSelect: (member) => selected.add(member.id),
                onBroadcastSelect: (_) {},
                availableWidth: 320,
              ),
            ),
          ),
          textScaler: scaler,
          overrides: [memberNamePreferDisplayProvider.overrideWithValue(false)],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '$label: no layout error');
      _expectNotVerticallyClamped(tester, 'Alexandria', label);

      await tester.tap(find.text('Alexandria'));
      await tester.pumpAndSettle();
      expect(selected, ['m1']);
    });

    testWidgets('broadcast row keeps both lines ($label)', (tester) async {
      _useCompactPhone(tester);
      final broadcast = <String>[];

      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: MentionOverlay(
                members: const [],
                filter: 'everyone',
                onSelect: (_) {},
                onBroadcastSelect: broadcast.add,
                availableWidth: 320,
              ),
            ),
          ),
          textScaler: scaler,
          overrides: [memberNamePreferDisplayProvider.overrideWithValue(false)],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '$label: no layout error');
      _expectNotVerticallyClamped(tester, '@everyone', label);
      _expectNotVerticallyClamped(
        tester,
        'Mention everyone in this chat',
        label,
      );

      await tester.tap(find.text('@everyone'));
      await tester.pumpAndSettle();
      expect(broadcast, isNotEmpty);
    });
  }

  testWidgets('default geometry: suggestion rows stay 48dp tall at 1x', (
    tester,
  ) async {
    _useCompactPhone(tester);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MentionOverlay(
              members: [_member('m1', 'Alexandria')],
              filter: 'alex',
              onSelect: (_) {},
              onBroadcastSelect: (_) {},
              availableWidth: 320,
            ),
          ),
        ),
        textScaler: const PrismTextScaler(TextScaler.noScaling, 1.0),
        overrides: [memberNamePreferDisplayProvider.overrideWithValue(false)],
      ),
    );
    await tester.pumpAndSettle();

    // Resolve the height from the paragraph the row really laid out - not from a
    // repainted assumption about its style. The row is max(48dp, one line + 8dp
    // above and below) and the list adds 4dp over and under it; the font stays at
    // full size, so a taller face legitimately asks for a taller row.
    final nameParagraph = tester.renderObject<RenderParagraph>(
      find.text('Alexandria'),
    );
    final lineHeight = nameParagraph.size.height;
    final surfaceContainer = tester.widget<Container>(
      find
          .ancestor(
            of: find.byType(ListView),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.decoration is BoxDecoration,
            ),
          )
          .first,
    );
    final decoration = surfaceContainer.decoration! as BoxDecoration;
    final borderInsets = decoration.padding.resolve(TextDirection.ltr);
    // The surface includes its decoration border outside the row/list padding.
    final expectedSurface =
        math.max(48.0, math.max(32.0, lineHeight) + 16) +
        8 +
        borderInsets.vertical;
    final surface = tester.getSize(
      find.byKey(const Key('mentionOverlaySurface')),
    );
    expect(
      surface.height,
      closeTo(expectedSurface, 0.5),
      reason:
          'a one-line name laid out at ${lineHeight.toStringAsFixed(1)}dp needs a '
          '${expectedSurface.toStringAsFixed(1)}dp surface at 1x',
    );
  });
}
