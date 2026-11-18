// The shared chrome height negotiation, exercised directly:
//
//  * `prismScaledPreferredSize(context, bar)` — the supported way to place a
//    growing bar in a fixed-extent slot. `Scaffold.appBar` caps its child at
//    `preferredSize.height + MediaQuery.padding.top`, and `preferredSize` is a
//    getter without a `BuildContext`, so a bar cannot grow there on its own. The
//    adapter resolves the content height with the caller's context; Scaffold adds
//    the status padding once, and the declared size must NOT include it again.
//  * `PrismSheetTopBar(titleWidget: …)` with a widget that reports its own height
//    must be contained (no fixed 180dp ceiling, measured at the real middle width).
//  * `SliverPinnedTopBar` leaves the bar unpinned when the viewport cannot hold
//    both it and a usable body, so a short window with the keyboard up scrolls
//    instead of squeezing the body to nothing.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

import 'chrome_text_scale_harness.dart';

/// A middle-slot widget that reports its own height, like a control does once it
/// adopts [PrismScaledHeight].
class _MeasuredBox extends StatelessWidget implements PrismScaledHeight {
  const _MeasuredBox({required this.height});

  final double height;

  @override
  double preferredHeightFor(BuildContext context, {double? availableWidth}) =>
      height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const ColoredBox(
        color: Color(0x11000000),
        child: Center(child: Text('measured middle')),
      ),
    );
  }
}

Widget _list({int count = 40}) => ListView.builder(
  itemCount: count,
  itemBuilder: (context, index) =>
      SizedBox(height: 48, child: Text('Row $index')),
);

class _CallCounter {
  int calls = 0;
}

/// A bar that reports a scalable height and counts how often it is measured, so
/// the sliver's cache can be checked without touching the real bars.
class _CountingBar extends StatelessWidget
    implements PreferredSizeWidget, PrismScaledHeight {
  const _CountingBar({required this.counter});

  final _CallCounter counter;

  @override
  Size get preferredSize => const Size.fromHeight(PrismTokens.topBarHeight);

  @override
  double preferredHeightFor(BuildContext context, {double? availableWidth}) {
    counter.calls += 1;
    return PrismTokens.topBarHeight +
        MediaQuery.textScalerOf(context).scale(10) +
        (availableWidth ?? 0) / 100000;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(child: Center(child: Text('Counting bar')));
  }
}

Widget _countingPage(_CountingBar bar) {
  return Scaffold(
    body: CustomScrollView(
      slivers: [
        SliverPinnedTopBar(child: bar),
        SliverList.builder(
          itemCount: 60,
          itemBuilder: (context, index) =>
              SizedBox(height: 48, child: Text('Row $index')),
        ),
      ],
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadChromeFonts();
  });

  testWidgets('prismScaledPreferredSize keeps a growing bar whole in '
      'Scaffold.appBar with a real status inset', (tester) async {
    useWindow(tester, compactPhone);
    const statusInset = 47.0;
    const title = 'Fronting schedule today';
    const subtitle = '12 headmates';

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(top: statusInset),
          viewPadding: EdgeInsets.only(top: statusInset),
        ),
        child: ProviderScope(
          child: chromeApp(
            Builder(
              builder: (context) {
                // Exactly the production migration shape: the bar is built where
                // the context exists, and its measured content height is declared
                // to the fixed-extent slot.
                const bar = PrismTopBar(title: title, subtitle: subtitle);
                return Scaffold(
                  appBar: prismScaledPreferredSize(context, bar),
                  body: _list(),
                );
              },
            ),
            system: 2.25,
            app: 1.5,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final barRect = tester.getRect(find.byType(PrismTopBar));
    expectNoLayoutException(tester, 'appBar adapter');

    // The bar occupies the status inset plus its measured content height, and the
    // inset appears exactly once: the title sits below the status area, and the
    // declared slot is not padded twice.
    expect(
      barRect.top,
      closeTo(0, 0.5),
      reason:
          'the app bar starts at the top of the window, under the status bar',
    );

    final titleRect = expectFullSizeText(
      tester,
      title,
      label: 'appBar adapter',
      container: barRect,
    );
    expectFullSizeText(
      tester,
      subtitle,
      label: 'appBar adapter (subtitle)',
      container: barRect,
    );
    expect(
      titleRect.top,
      greaterThanOrEqualTo(statusInset - 0.5),
      reason: 'the title must not paint under the status bar',
    );

    // The reserved extent is the bar's content height, plus the inset Scaffold
    // adds itself - i.e. exactly the painted bar, with no empty status band.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final appBar = scaffold.appBar!;
    expect(
      appBar.preferredSize.height + statusInset,
      closeTo(barRect.height, 0.5),
      reason:
          'declared ${appBar.preferredSize.height} + inset $statusInset must '
          'equal the painted ${barRect.height}, so the inset is not added twice',
    );
  });

  testWidgets('a bar mounted directly in Scaffold.appBar only reserves its '
      'minimum (documented limitation)', (tester) async {
    useWindow(tester, compactPhone);
    const title = 'Fronting schedule today';

    await tester.pumpWidget(
      ProviderScope(
        child: chromeApp(
          const Scaffold(
            appBar: PrismTopBar(title: title),
            body: SizedBox.shrink(),
          ),
          system: 2.25,
          app: 1.5,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The legacy constructor cannot grow from a context-free getter, so a direct
    // mount reserves only the 66dp minimum and the bar paints outside it at large
    // text. This is the limitation the adapter exists for; it is asserted here so
    // nobody mistakes the getter for a fix.
    final barRect = tester.getRect(find.byType(PrismTopBar));
    expect(
      barRect.height,
      closeTo(PrismTokens.topBarHeight, 0.5),
      reason: 'the legacy mount reserves only preferredSize (the minimum)',
    );
    final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
    expect(
      paragraph.size.height,
      greaterThan(PrismTokens.topBarHeight),
      reason:
          'the title needs more than the slot the legacy mount reserved '
          '(${neededHeight(paragraph).toStringAsFixed(1)}px at 3.375x)',
    );
    expect(
      tester.getRect(find.text(title)).bottom,
      greaterThan(barRect.bottom + 0.5),
      reason:
          'the title paints outside the reserved slot: use '
          'prismScaledPreferredSize(context, bar), not a direct appBar mount',
    );
    // The overflow is the documented consequence; clear it so this test reports
    // the assertions above rather than the framework error.
    tester.takeException();
  });

  testWidgets('PrismSheetTopBar measures a titleWidget that reports its own '
      'height and contains it', (tester) async {
    useWindow(tester, compactPhone);
    await tester.pumpWidget(
      ProviderScope(
        child: chromeApp(
          Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  const PrismSheetTopBar(
                    title: 'Segmented title',
                    titleWidget: _MeasuredBox(height: 120),
                  ),
                  Expanded(child: _list(count: 5)),
                ],
              ),
            ),
          ),
          system: 2.25,
          app: 1.5,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final barRect = tester.getRect(find.byType(PrismSheetTopBar));
    final middleRect = tester.getRect(find.text('measured middle'));
    expect(
      barRect.height,
      greaterThanOrEqualTo(120 + 12 - 0.5),
      reason:
          'the bar must reserve the middle widget height plus its breathing',
    );
    expect(middleRect.top, greaterThanOrEqualTo(barRect.top - 0.5));
    expect(
      middleRect.bottom,
      lessThanOrEqualTo(barRect.bottom + 0.5),
      reason: 'the measured middle widget is contained, not clipped',
    );
    expectNoLayoutException(tester, 'measured titleWidget');
  });

  testWidgets('a real segmented titleWidget stays inside the sheet bar', (
    tester,
  ) async {
    useWindow(tester, compactPhone);
    await tester.pumpWidget(
      ProviderScope(
        child: chromeApp(
          Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  PrismSheetTopBar(
                    title: 'Tabs',
                    titleWidget: PrismSegmentedControl<int>(
                      segments: const [
                        PrismSegment(value: 0, label: 'Edit'),
                        PrismSegment(value: 1, label: 'Style'),
                      ],
                      selected: 0,
                      onChanged: (_) {},
                    ),
                  ),
                  Expanded(child: _list(count: 5)),
                ],
              ),
            ),
          ),
          system: 2.25,
          app: 1.5,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final barRect = tester.getRect(find.byType(PrismSheetTopBar));
    final track = tester.getRect(
      find.byWidgetPredicate((widget) => widget is PrismSegmentedControl),
    );
    expect(track.top, greaterThanOrEqualTo(barRect.top - 0.5));
    expect(
      track.bottom,
      lessThanOrEqualTo(barRect.bottom + 0.5),
      reason: 'the switcher is contained by the sheet bar at 3.375x',
    );
    expectNoLayoutException(tester, 'segmented titleWidget');
  });

  testWidgets('a pinned bar scrolls away instead of squeezing the body on a '
      'short viewport', (tester) async {
    // Landscape-ish height with a software keyboard up: the bar needs more room
    // than the viewport leaves for a usable body.
    useWindow(tester, const Size(320, 200), keyboardInset: 90);
    const title = 'Timeline';
    await tester.pumpWidget(
      ProviderScope(
        child: chromeApp(
          PrismPageScaffold(
            topBar: const PrismTopBar(title: title, subtitle: '12 headmates'),
            // Opt-in: a composite/growing header asks for room below itself. The
            // default (0) keeps ordinary bars pinned whenever they fit at all.
            topBarMinBodyExtent: 96,
            body: _list(count: 20),
          ),
          system: 2.25,
          app: 1.5,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final barBefore = tester.getRect(find.byType(PrismTopBar));
    expectNoLayoutException(tester, 'short viewport');
    expectFullSizeText(
      tester,
      title,
      label: 'short viewport',
      container: barBefore,
    );

    // Not pinned: the header is part of the scroll extent, so the outer position
    // advances and the body stays usable. The bar is not read again afterwards —
    // once it scrolls out of view the sliver may legitimately not build it.
    final outer = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(
      outer.position.maxScrollExtent,
      greaterThan(0),
      reason: 'a short viewport must be scrollable, not clipped',
    );
    outer.position.jumpTo(outer.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(
      outer.position.pixels,
      greaterThan(0),
      reason:
          'the bar must scroll with the content when the viewport is too short',
    );
    expect(
      tester.getRect(find.byType(ListView)).height,
      greaterThan(0),
      reason: 'the body keeps a scrollable area',
    );
  });

  testWidgets(
    'a plain 66dp bar still pins in a very short viewport (default is '
    'unchanged)',
    (tester) async {
      // A bare 66dp bar (default text size) in a very short viewport: no body
      // minimum is requested, so pinning is exactly as before.
      useWindow(tester, const Size(320, 150));
      const title = 'Members';
      await tester.pumpWidget(
        ProviderScope(
          child: chromeApp(
            PrismPageScaffold(
              topBar: const PrismTopBar(title: title),
              body: _list(count: 20),
            ),
            system: 1.0,
            app: 1.0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expectNoLayoutException(tester, 'short viewport, plain bar');

      final barBefore = tester.getRect(find.byType(PrismTopBar));
      // Still pinned: scrolling does not move it. Only headers that opt in to a
      // body minimum give up pinning.
      await tester.drag(find.byType(ListView), const Offset(0, -80));
      await tester.pumpAndSettle();
      final barAfter = tester.getRect(find.byType(PrismTopBar));
      expect(
        barAfter.top,
        closeTo(barBefore.top, 0.5),
        reason:
            'a plain bar keeps today\'s pinning behaviour on a short viewport',
      );
    },
  );

  testWidgets('the sliver measures a bar once per input, not once per scroll '
      'frame', (tester) async {
    useWindow(tester, const Size(320, 640));
    final counter = _CallCounter();
    final bar = _CountingBar(counter: counter);

    await tester.pumpWidget(
      ProviderScope(
        child: chromeApp(
          _countingPage(bar),
          system: 1.0,
          app: 1.0,
          scalerOverride: const TextScaler.linear(1.0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final afterFirstLayout = counter.calls;
    expect(afterFirstLayout, greaterThan(0));

    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
      await tester.pump();
    }
    expect(
      counter.calls,
      afterFirstLayout,
      reason:
          'scrolling at a stable width and scale must not re-measure the bar '
          '(${counter.calls} vs $afterFirstLayout)',
    );

    // A text-scale change with the same widget instance must re-measure.
    await tester.pumpWidget(
      ProviderScope(
        child: chromeApp(
          _countingPage(bar),
          system: 1.0,
          app: 1.0,
          scalerOverride: const TextScaler.linear(2.0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final afterScaleChange = counter.calls;
    expect(
      afterScaleChange,
      greaterThan(afterFirstLayout),
      reason: 'a new text scale must invalidate the cached height',
    );

    // A width change with the same widget instance must re-measure too.
    useWindow(tester, const Size(400, 640));
    await tester.pumpAndSettle();
    expect(
      counter.calls,
      greaterThan(afterScaleChange),
      reason: 'a new cross-axis width must invalidate the cached height',
    );
  });
}
