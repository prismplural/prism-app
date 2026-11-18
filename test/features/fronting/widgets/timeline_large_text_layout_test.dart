// Simulated large-text layout tests for the timeline member header row.
//
// Scenario: 225% system text size x 150% Prism font-size preference, composed
// the way app.dart does it with PrismTextScaler, so header labels scale by
// 3.375. These are simulated layout tests - they do not reproduce the reporter's
// captured settings and they do not qualify any native Windows build. They
// render the real TimelineView with real bundled faces (OpenDyslexic plus an
// emoji fallback, not the square test font) and assert observable layout, not
// implementation: the sticky header grows instead of clipping its names,
// ordinary names stay readable instead of collapsing to one initial, header
// columns stay aligned with the painted grid after horizontal scrolling, and a
// tap still opens the intended member's session.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_painter.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_view.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

import '../../../helpers/fake_repositories.dart';
import '../../../helpers/prism_golden.dart' show loadPrismGoldenFonts;

/// The scenario's system text-size factor: Windows accessibility text size at
/// its maximum, 225%.
const TextScaler _windowsMaxSystemScaler = TextScaler.linear(2.25);

/// The scenario's Prism font-size factor: the app clamps its preference to
/// 150% (`FontFamily.maximumScale`).
const double _appMaxFontScale = 1.5;

/// Today's compact header band; default text size must keep it.
const double _defaultHeaderBandHeight = 56;

/// A nonlinear accessibility scaler, like the platform-provided ones that
/// PrismTextScaler delegates each size to instead of assuming a linear factor.
class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize <= 14 ? fontSize * 2.5 : 35 + (fontSize - 14) * 0.4;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 2.5;
}

Finder _timelineCanvasFinder() => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is TimelinePainter,
);

TimelinePainter _timelinePainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_timelineCanvasFinder()).painter!
        as TimelinePainter;

Rect _timelineCanvasRect(WidgetTester tester) =>
    tester.getRect(_timelineCanvasFinder());

/// The vertical scroller holding the grid, i.e. everything below the sticky
/// header band and its one-pixel divider. Its top edge is the band's bottom.
/// Anchored on the canvas so a header that has to scroll vertically in a short
/// window can never be mistaken for it.
Finder _gridScrollViewFinder() => find
    .ancestor(
      of: _timelineCanvasFinder(),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.vertical,
      ),
    )
    .first;

double _headerBandHeight(WidgetTester tester) {
  final viewTop = tester.getTopLeft(find.byType(TimelineView)).dy;
  final gridTop = tester.getTopLeft(_gridScrollViewFinder()).dy;
  return gridTop - viewTop - 1;
}

/// Laid-out glyph boxes for the visible part of a header name.
List<ui.TextBox> _nameBoxes(RenderParagraph paragraph, String name) =>
    paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: name.length),
    );

/// Number of rendered text lines, from the laid-out glyph boxes.
int _nameLineCount(RenderParagraph paragraph, String name) =>
    {for (final box in _nameBoxes(paragraph, name)) box.top.round()}.length;

/// Asserts a header label is laid out at the full composed scale of the
/// scenario, so a font cap, a forced strut or a reduced scaler cannot pass.
void _expectComposedScale(
  RenderParagraph paragraph,
  double expectedScale, {
  required int expectedLines,
}) {
  final style = paragraph.text.style!;
  final fontSize = style.fontSize!;
  expect(style.height, isNotNull);
  expect(
    paragraph.textScaler.scale(fontSize),
    closeTo(fontSize * expectedScale, 1e-6),
    reason: 'the header must inherit the composed system x Prism text scaler',
  );
  expect(
    paragraph.size.height,
    closeTo(fontSize * style.height! * expectedScale * expectedLines, 0.5),
    reason: 'laid-out lines must use the full scaled size, not a capped one',
  );
}

RenderParagraph _nameParagraph(WidgetTester tester, String name) {
  final finder = find.text(name);
  expect(
    finder,
    findsOneWidget,
    reason: 'the header must render exactly one label for "$name"',
  );
  return tester.renderObject<RenderParagraph>(finder);
}

List<Member> _members(List<String> names) => [
  for (var i = 0; i < names.length; i++)
    Member(
      id: 'member-$i',
      name: names[i],
      createdAt: DateTime(2026, 1, 1),
      displayOrder: i,
    ),
];

/// One active session per member, so every column has a bar that spans "now".
FakeFrontingSessionRepository _repoFor(List<Member> members) {
  final repo = FakeFrontingSessionRepository();
  final now = DateTime.now();
  for (final member in members) {
    repo.sessions.add(
      FrontingSession(
        id: '${member.id}-session',
        memberId: member.id,
        startTime: now.subtract(const Duration(hours: 2)),
      ),
    );
  }
  return repo;
}

ProviderContainer _container(
  FakeFrontingSessionRepository repo,
  List<Member> members,
) {
  final memberRepo = FakeMemberRepository()..seed(members);
  return ProviderContainer(
    overrides: [
      frontingSessionRepositoryProvider.overrideWithValue(repo),
      memberRepositoryProvider.overrideWithValue(memberRepo),
      allMembersProvider.overrideWith((ref) => Stream.value(members)),
      recentSleepSessionsPaginatedProvider.overrideWith(
        (ref, limit) => Stream.value(const <FrontingSession>[]),
      ),
    ],
  );
}

/// Real bundled faces, loaded once in `setUpAll` through the repository's
/// platform-gated loader (rootBundle first, on-disk asset as fallback).
/// OpenDyslexic has production-like advances and line metrics that the square
/// test font hides; the emoji fallback covers emoji inside member names.
ThemeData _timelineTheme() => ThemeData(
  fontFamily: 'OpenDyslexic',
  fontFamilyFallback: const ['NotoColorEmoji'],
);

Widget _buildSubject(
  ProviderContainer container, {
  TextScaler? systemScaler,
  double appFontScale = 1.0,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: _timelineTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (systemScaler == null) return content;
        // Mirrors app.dart: the app factor is applied on top of the system
        // accessibility scaler through PrismTextScaler, per size.
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: PrismTextScaler(systemScaler, appFontScale)),
          child: content,
        );
      },
      home: const Scaffold(body: TimelineView()),
    ),
  );
}

void _useWindow(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpTimeline(
  WidgetTester tester,
  ProviderContainer container, {
  TextScaler? systemScaler,
  double appFontScale = 1.0,
}) async {
  await tester.pumpWidget(
    _buildSubject(
      container,
      systemScaler: systemScaler,
      appFontScale: appFontScale,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadPrismGoldenFonts();
  });

  testWidgets('large text keeps fitting columns to the changing window width', (
    tester,
  ) async {
    final members = _members(['Wren', 'Nico', 'Ash', 'Ivy']);
    final container = _container(_repoFor(members), members);
    addTearDown(container.dispose);
    final widths = <double>[];
    for (final window in [600.0, 800.0, 900.0, 1100.0]) {
      _useWindow(tester, Size(window, 700));
      await _pumpTimeline(
        tester,
        container,
        systemScaler: _windowsMaxSystemScaler,
        appFontScale: _appMaxFontScale,
      );
      expect(tester.takeException(), isNull);
      final expected =
          ((window - 52) / 4).clamp(
            40 * 3.375,
            (window >= 900 ? 68 : 52) * 3.375,
          ) -
          4;
      final width = _timelinePainter(tester).columnWidth;
      expect(
        width,
        closeTo(expected, .01),
        reason:
            'Large text must retain distinct scaled minimum and maximum bounds.',
      );
      widths.add(width);
      _expectComposedScale(
        _nameParagraph(tester, 'Nico'),
        3.375,
        expectedLines: 1,
      );
    }
    expect(
      widths.toSet().length,
      4,
      reason: 'Resizing must not leave every column locked to one width.',
    );
  });

  testWidgets('large text keeps fitting columns to the member count', (
    tester,
  ) async {
    _useWindow(tester, const Size(800, 700));
    final widths = <double>[];
    for (final count in [2, 5, 20]) {
      final members = _members([for (var i = 0; i < count; i++) 'Nico $i']);
      final container = _container(_repoFor(members), members);
      try {
        await _pumpTimeline(
          tester,
          container,
          systemScaler: _windowsMaxSystemScaler,
          appFontScale: _appMaxFontScale,
        );
        expect(tester.takeException(), isNull);
        final width = _timelinePainter(tester).columnWidth;
        expect(
          width,
          closeTo(((800 - 52) / count).clamp(40 * 3.375, 52 * 3.375) - 4, .01),
        );
        widths.add(width);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        container.dispose();
        await tester.pump();
      }
    }
    expect(widths[0], greaterThan(widths[1]));
    expect(widths[1], greaterThan(widths[2]));
  });

  testWidgets('short names at large text reserve only the line they need', (
    tester,
  ) async {
    _useWindow(tester, const Size(1200, 700));
    final members = _members(['Nico', 'Ash']);
    final container = _container(_repoFor(members), members);
    addTearDown(container.dispose);
    await _pumpTimeline(
      tester,
      container,
      systemScaler: _windowsMaxSystemScaler,
      appFontScale: _appMaxFontScale,
    );
    final name = _nameParagraph(tester, 'Nico');
    expect(
      name.maxLines,
      1,
      reason:
          'Larger type alone is not a reason to reserve an empty second line.',
    );
    _expectComposedScale(name, 3.375, expectedLines: 1);
    final style = name.text.style!;
    final lineHeight = style.fontSize! * style.height! * 3.375;
    expect(_headerBandHeight(tester), lessThan(28 + 2 + 2 * lineHeight));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'widening the timeline releases an unnecessary wrapped name line',
    (tester) async {
      final members = _members(['Nico Nico', 'Nico']);
      final container = _container(_repoFor(members), members);
      addTearDown(container.dispose);
      _useWindow(tester, const Size(600, 700));
      await _pumpTimeline(
        tester,
        container,
        systemScaler: _windowsMaxSystemScaler,
        appFontScale: _appMaxFontScale,
      );
      expect(
        _nameLineCount(_nameParagraph(tester, 'Nico Nico'), 'Nico Nico'),
        2,
      );
      final narrowBand = _headerBandHeight(tester);
      tester.view.physicalSize = const Size(1200, 700);
      await tester.pumpAndSettle();
      final name = _nameParagraph(tester, 'Nico Nico');
      expect(name.maxLines, 1);
      expect(name.didExceedMaxLines, isFalse);
      expect(_headerBandHeight(tester), lessThan(narrowBand));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small text keeps avatar-safe columns and the compact band', (
    tester,
  ) async {
    _useWindow(tester, const Size(800, 700));
    final members = _members([for (var i = 0; i < 40; i++) 'Nico $i']);
    final container = _container(_repoFor(members), members);
    addTearDown(container.dispose);
    await _pumpTimeline(
      tester,
      container,
      systemScaler: const TextScaler.linear(1),
      appFontScale: .5,
    );
    expect(_timelinePainter(tester).columnWidth, 36);
    expect(_headerBandHeight(tester), 56);
    _expectComposedScale(
      _nameParagraph(tester, 'Nico 0'),
      .5,
      expectedLines: 1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'default text size (100% x 100%) keeps the compact 56 px band and narrow '
    'columns',
    (tester) async {
      _useWindow(tester, const Size(800, 700));
      final members = _members([for (var i = 0; i < 40; i++) 'Member $i']);
      final container = _container(_repoFor(members), members);
      addTearDown(container.dispose);

      await _pumpTimeline(tester, container);

      expect(tester.takeException(), isNull);
      expect(
        _headerBandHeight(tester),
        closeTo(_defaultHeaderBandHeight, 0.01),
      );
      final painter = _timelinePainter(tester);
      expect(
        painter.columnWidth,
        closeTo(36, 0.01),
        reason: 'default text size keeps the existing 36 px column floor',
      );

      final canvasRect = _timelineCanvasRect(tester);
      final zones = painter.computeHitZones(canvasRect.size);
      final firstZone = zones.firstWhere(
        (zone) => zone.session.memberId == 'member-0',
      );
      expect(firstZone.rect.width, closeTo(painter.columnWidth, 0.01));
      expect(
        tester.getCenter(find.text('Member 0')).dx,
        closeTo(canvasRect.left + firstZone.rect.center.dx, 1),
        reason: 'header columns must stay centered over their grid columns',
      );
    },
  );

  testWidgets(
    '225% system x 150% Prism scaling grows the header instead of clipping '
    'names',
    (tester) async {
      _useWindow(tester, const Size(800, 700));
      final members = _members([
        'Alexandria',
        'Bartholomew Thistlewood',
        'Wren',
        'Ash',
        'Moth',
        'Sable',
        'Ivy',
        'Rowan',
        'Juniper',
        'Caspian',
        'Thistle',
        'Vesper',
        'Ember',
        'Dandelion',
      ]);
      final container = _container(_repoFor(members), members);
      addTearDown(container.dispose);

      await _pumpTimeline(
        tester,
        container,
        systemScaler: _windowsMaxSystemScaler,
        appFontScale: _appMaxFontScale,
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'names must not overflow the sticky header band',
      );
      final band = _headerBandHeight(tester);
      expect(
        band,
        greaterThan(_defaultHeaderBandHeight),
        reason: 'the header band has to grow with the scaled name text',
      );

      expect(
        tester.getSize(_gridScrollViewFinder()).height,
        closeTo(700 - band - 1, 0.5),
        reason:
            'the taller header must reduce the grid viewport, not overlap it',
      );

      final viewTop = tester.getTopLeft(find.byType(TimelineView)).dy;
      final bandBottom = tester.getTopLeft(_gridScrollViewFinder()).dy - 1;
      for (final name in ['Alexandria', 'Bartholomew Thistlewood', 'Wren']) {
        final rect = tester.getRect(find.text(name));
        expect(rect.top, greaterThanOrEqualTo(viewTop));
        expect(
          rect.bottom,
          lessThanOrEqualTo(bandBottom),
          reason:
              '"$name" must be laid out inside the header band, not clipped',
        );
      }

      final ordinary = _nameParagraph(tester, 'Alexandria');
      expect(
        ordinary.didExceedMaxLines,
        isFalse,
        reason:
            'a 10-character name must stay fully readable at maximum text '
            'size, not collapse to a single initial',
      );
      expect(
        _nameLineCount(ordinary, 'Alexandria'),
        greaterThanOrEqualTo(2),
        reason: 'large text wraps names over two lines instead of truncating',
      );
      _expectComposedScale(
        ordinary,
        _windowsMaxSystemScaler.scale(1) * _appMaxFontScale,
        expectedLines: 2,
      );

      final long = _nameParagraph(tester, 'Bartholomew Thistlewood');
      expect(
        long.didExceedMaxLines,
        isTrue,
        reason: 'unbounded names still ellipsize rather than widen forever',
      );
      expect(
        find.byTooltip('Bartholomew Thistlewood'),
        findsOneWidget,
        reason: 'an ellipsized name keeps its full text as an accessible label',
      );

      final painter = _timelinePainter(tester);
      expect(
        painter.columnWidth,
        greaterThan(48),
        reason:
            'columns widen past the default 48 px cap so names stay readable '
            'instead of squeezing every member into the window',
      );
      final canvasRect = _timelineCanvasRect(tester);
      final zones = painter.computeHitZones(canvasRect.size);
      final firstZone = zones.firstWhere(
        (zone) => zone.session.memberId == 'member-0',
      );
      expect(
        tester.getCenter(find.text('Alexandria')).dx,
        closeTo(canvasRect.left + firstZone.rect.center.dx, 1),
        reason: 'widened columns stay aligned between header and grid',
      );
    },
  );

  testWidgets(
    'short window at 225% x 150% falls back to a scrollable header without '
    'shrinking text',
    (tester) async {
      _useWindow(tester, const Size(420, 180));
      final members = _members(['Wren', 'Bartholomew Thistlewood', 'Moth']);
      final container = _container(_repoFor(members), members);
      addTearDown(container.dispose);

      await _pumpTimeline(
        tester,
        container,
        systemScaler: _windowsMaxSystemScaler,
        appFontScale: _appMaxFontScale,
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'a short window must not overflow the header or the grid',
      );
      final band = _headerBandHeight(tester);
      expect(band, greaterThan(0));
      expect(
        band,
        lessThanOrEqualTo(180 - 1),
        reason: 'the header band cannot take more than the window height',
      );
      expect(
        tester.getSize(_gridScrollViewFinder()).height,
        greaterThan(0),
        reason: 'the grid keeps a usable viewport, never a negative one',
      );

      // This case must still reach the capped-header fallback after short
      // names have become eligible for a compact, single-line header.
      final headerScroll = find.ancestor(
        of: find.text('Wren'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.vertical,
        ),
      );
      expect(headerScroll, findsOneWidget);
      await tester.drag(headerScroll, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text('Bartholomew Thistlewood')).dy,
        lessThanOrEqualTo(tester.getTopLeft(_gridScrollViewFinder()).dy),
      );

      // The inherited scaler and the laid-out line height are both exact, so a
      // reduced scale cannot pass this by accident.
      _expectComposedScale(
        _nameParagraph(tester, 'Wren'),
        _windowsMaxSystemScaler.scale(1) * _appMaxFontScale,
        expectedLines: 1,
      );
    },
  );

  testWidgets(
    'default text size keeps the band, the name row and the avatar row aligned',
    (tester) async {
      _useWindow(tester, const Size(900, 700));
      final members = _members(['Alexandria', 'Nico']);
      final container = _container(_repoFor(members), members);
      addTearDown(container.dispose);

      await _pumpTimeline(tester, container);

      expect(tester.takeException(), isNull);
      expect(
        _headerBandHeight(tester),
        closeTo(_defaultHeaderBandHeight, 0.01),
      );
      expect(
        _timelinePainter(tester).columnWidth,
        closeTo(64, 0.01),
        reason: 'a 900 px window keeps the wide column maximum',
      );
      final avatars = find.byType(MemberAvatar);
      expect(avatars, findsNWidgets(2));
      expect(
        tester.getRect(avatars.at(0)).top,
        closeTo(tester.getRect(avatars.at(1)).top, 0.5),
      );
      expect(
        tester.getRect(find.text('Alexandria')).top,
        closeTo(tester.getRect(find.text('Nico')).top, 0.5),
      );
    },
  );

  testWidgets(
    'emoji, RTL and unbounded names stay inside the grown header band at '
    '225% x 150%',
    (tester) async {
      _useWindow(tester, const Size(900, 700));
      final names = ['🜁 Wren', 'نور', 'Alexandria', 'Bartholomew Thistlewood'];
      final members = _members(names);
      final container = _container(_repoFor(members), members);
      addTearDown(container.dispose);

      await _pumpTimeline(
        tester,
        container,
        systemScaler: _windowsMaxSystemScaler,
        appFontScale: _appMaxFontScale,
      );

      expect(tester.takeException(), isNull);
      final viewTop = tester.getTopLeft(find.byType(TimelineView)).dy;
      final bandBottom = tester.getTopLeft(_gridScrollViewFinder()).dy - 1;
      for (final name in names) {
        final finder = find.text(name);
        if (finder.evaluate().isEmpty) continue; // column scrolled out of view
        final rect = tester.getRect(finder);
        expect(rect.top, greaterThanOrEqualTo(viewTop));
        expect(
          rect.bottom,
          lessThanOrEqualTo(bandBottom),
          reason: '"$name" must fit inside the header band',
        );
        expect(
          find.byTooltip(name),
          findsOneWidget,
          reason: '"$name" keeps a full-name accessible label',
        );
        // Fallback faces (emoji) can draw taller ink than the primary face, so
        // check the glyph boxes, not only the paragraph box.
        final paragraph = _nameParagraph(tester, name);
        final boxes = _nameBoxes(paragraph, name);
        expect(
          boxes,
          isNotEmpty,
          reason: '"$name" must render glyphs, including fallback ink',
        );
        for (final box in boxes) {
          expect(
            rect.top + box.top,
            greaterThanOrEqualTo(viewTop),
            reason: '"$name" fallback ink must not clip at the band top',
          );
          expect(
            rect.top + box.bottom,
            lessThanOrEqualTo(bandBottom),
            reason: '"$name" fallback ink must not clip at the band bottom',
          );
        }
      }

      final rtl = _nameParagraph(tester, 'نور');
      expect(_nameBoxes(rtl, 'نور'), isNotEmpty);
      expect(rtl.size.width, greaterThan(0));
    },
  );

  testWidgets(
    'one-line and two-line names keep avatars and first baselines level at '
    '225% x 150%',
    (tester) async {
      _useWindow(tester, const Size(900, 700));
      final names = ['Alexandria', 'Nico', 'Ash', 'Bartholomew Thistlewood'];
      final members = _members(names);
      final container = _container(_repoFor(members), members);
      addTearDown(container.dispose);

      await _pumpTimeline(
        tester,
        container,
        systemScaler: _windowsMaxSystemScaler,
        appFontScale: _appMaxFontScale,
      );

      expect(tester.takeException(), isNull);
      // The case is only meaningful with genuinely mixed name heights.
      expect(
        _nameLineCount(_nameParagraph(tester, 'Alexandria'), 'Alexandria'),
        2,
      );
      expect(_nameLineCount(_nameParagraph(tester, 'Nico'), 'Nico'), 1);

      final avatars = find.byType(MemberAvatar);
      final avatarCount = avatars.evaluate().length;
      expect(avatarCount, greaterThanOrEqualTo(3));
      final avatarTops = [
        for (var i = 0; i < avatarCount; i++) tester.getRect(avatars.at(i)).top,
      ];
      for (final top in avatarTops) {
        expect(
          top,
          closeTo(avatarTops.first, 0.5),
          reason:
              'avatar rows must stay level whether a name takes one line or '
              'two; a short name must not drag its avatar down',
        );
      }
      for (var i = 0; i < avatarCount; i++) {
        expect(tester.getRect(avatars.at(i)).height, closeTo(28, 0.5));
      }

      final nameTops = <String, double>{};
      for (final name in names) {
        final finder = find.text(name);
        if (finder.evaluate().isEmpty) continue; // column scrolled out of view
        nameTops[name] = tester.getRect(finder).top;
      }
      expect(nameTops.length, greaterThanOrEqualTo(3));
      final referenceTop = nameTops['Alexandria']!;
      for (final entry in nameTops.entries) {
        expect(
          entry.value,
          closeTo(referenceTop, 0.5),
          reason:
              '"${entry.key}" must start on the same first-name baseline as '
              'the two-line names',
        );
      }
    },
  );

  testWidgets(
    'accented and descending names keep their glyph ink inside the band at '
    '225% x 150%',
    (tester) async {
      _useWindow(tester, const Size(900, 700));
      final names = ['ÉÅgjpq', 'Éowyn Åse', 'gjpqy ģ', 'Wren'];
      final members = _members(names);
      final container = _container(_repoFor(members), members);
      addTearDown(container.dispose);

      await _pumpTimeline(
        tester,
        container,
        systemScaler: _windowsMaxSystemScaler,
        appFontScale: _appMaxFontScale,
      );

      expect(tester.takeException(), isNull);
      final viewTop = tester.getTopLeft(find.byType(TimelineView)).dy;
      final bandBottom = tester.getTopLeft(_gridScrollViewFinder()).dy - 1;

      var checked = 0;
      for (final name in names) {
        final finder = find.text(name);
        if (finder.evaluate().isEmpty) continue; // column scrolled out of view
        final paragraph = _nameParagraph(tester, name);
        final origin = tester.getTopLeft(finder);
        final boxes = _nameBoxes(paragraph, name);
        expect(boxes, isNotEmpty, reason: '"$name" must render glyphs');
        for (final box in boxes) {
          expect(
            origin.dy + box.top,
            greaterThanOrEqualTo(viewTop),
            reason: '"$name" ink must not be clipped at the band top',
          );
          expect(
            origin.dy + box.bottom,
            lessThanOrEqualTo(bandBottom),
            reason: '"$name" ink must not be clipped at the band bottom',
          );
        }
        checked++;
      }
      expect(
        checked,
        greaterThanOrEqualTo(3),
        reason: 'the accented/descender columns must actually be rendered',
      );
      _expectComposedScale(
        _nameParagraph(tester, 'ÉÅgjpq'),
        _windowsMaxSystemScaler.scale(1) * _appMaxFontScale,
        expectedLines: 1,
      );
    },
  );

  testWidgets(
    'scrolling to the last member keeps header and grid aligned and taps it',
    (tester) async {
      _useWindow(tester, const Size(500, 800));
      final members = _members([
        'Wren',
        'Ash',
        'Moth',
        'Juniper',
        'Rowan',
        'Vesper',
      ]);
      final container = _container(_repoFor(members), members);
      addTearDown(container.dispose);

      // Scenario variant at system 150% x Prism 150%: still a combined
      // large-text layout, but the preview sheet itself stays out of the
      // extreme range that other tests cover.
      await _pumpTimeline(
        tester,
        container,
        systemScaler: const TextScaler.linear(1.5),
        appFontScale: 1.5,
      );

      expect(
        _timelinePainter(tester).columnWidth,
        greaterThan(48),
        reason: 'large text widens columns instead of squeezing every member',
      );

      // The canvas center is far below the viewport, so scroll from the grid
      // viewport itself: the inner horizontal scroller claims the drag.
      await tester.drag(_gridScrollViewFinder(), const Offset(-4000, 0));
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Vesper'),
        findsOneWidget,
        reason: 'the last member header scrolls into view with the grid',
      );

      final painter = _timelinePainter(tester);
      final canvasRect = _timelineCanvasRect(tester);
      final zones = painter.computeHitZones(canvasRect.size);
      final lastZone = zones.firstWhere(
        (zone) => zone.session.memberId == 'member-5',
      );
      expect(
        tester.getCenter(find.text('Vesper')).dx,
        closeTo(canvasRect.left + lastZone.rect.center.dx, 1),
        reason:
            'after horizontal scrolling the header column is still centered '
            'over its grid column',
      );

      await tester.tapAt(canvasRect.topLeft + lastZone.rect.center);
      await tester.pumpAndSettle();

      expect(find.text('View Details'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Vesper'),
        ),
        findsOneWidget,
        reason: 'the tap opens the session of the column that was tapped',
      );
    },
  );

  testWidgets(
    'zooming out at 225% x 150% keeps the culling offset inside the canvas',
    (tester) async {
      _useWindow(tester, const Size(800, 700));
      final members = _members(['Wren']);
      final repo = FakeFrontingSessionRepository();
      final now = DateTime.now();
      repo.sessions.add(
        FrontingSession(
          id: 'long-session',
          memberId: 'member-0',
          startTime: now.subtract(const Duration(days: 21)),
          endTime: now,
        ),
      );
      final container = _container(repo, members);
      addTearDown(container.dispose);

      await _pumpTimeline(
        tester,
        container,
        systemScaler: _windowsMaxSystemScaler,
        appFontScale: _appMaxFontScale,
      );

      expect(_headerBandHeight(tester), greaterThan(_defaultHeaderBandHeight));
      expect(
        _timelinePainter(tester).scrollOffsetNotifier!.value,
        lessThanOrEqualTo(tester.getSize(_timelineCanvasFinder()).height),
      );

      final notifier = container.read(timelineStateProvider.notifier);
      while (container.read(timelineStateProvider).pixelsPerHour >
          TimelineState.minPixelsPerHour) {
        notifier.zoomOut();
        await tester.pump();
      }

      expect(
        _timelinePainter(tester).scrollOffsetNotifier!.value,
        lessThanOrEqualTo(tester.getSize(_timelineCanvasFinder()).height),
        reason: 'a taller header must not leave a stale culling offset',
      );
    },
  );

  testWidgets('nonlinear system scaling composes with the Prism font scale', (
    tester,
  ) async {
    _useWindow(tester, const Size(800, 700));
    final members = _members([
      'Alexandria',
      'Wren',
      'Ash',
      'Moth',
      'Sable',
      'Ivy',
      'Rowan',
      'Juniper',
    ]);
    final container = _container(_repoFor(members), members);
    addTearDown(container.dispose);

    await _pumpTimeline(
      tester,
      container,
      systemScaler: const _NonlinearTextScaler(),
      appFontScale: _appMaxFontScale,
    );

    expect(tester.takeException(), isNull);
    expect(_headerBandHeight(tester), greaterThan(_defaultHeaderBandHeight));
    final paragraph = _nameParagraph(tester, 'Alexandria');
    expect(paragraph.didExceedMaxLines, isFalse);
    final bandBottom = tester.getTopLeft(_gridScrollViewFinder()).dy - 1;
    expect(
      tester.getRect(find.text('Alexandria')).bottom,
      lessThanOrEqualTo(bandBottom),
    );
    expect(
      _timelinePainter(tester).columnWidth,
      greaterThan(48),
      reason: 'the nonlinear scaler still widens columns past the default cap',
    );
  });
}
