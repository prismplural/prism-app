// Cache regressions for the pinned-header extent (`SliverPinnedTopBar` caches the
// measured height and must invalidate it on every input that can change it).
//
// Case 1: a fixed-width pane. The sliver's cross-axis extent does not change
// while the *window* crosses PrismTokens.desktopBreakpoint (768), which is what
// PrismTopBar uses to choose its title size (22 -> 18). The bar therefore needs a
// different height although the child instance, theme, scaler and sliver width
// are all identical: the band must follow the bar, and the title must still be
// painted at its requested size.
//
// Case 2: the sliver width itself changes at a constant window. That is a cache
// key, so the bar must be measured again at the new width.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';

import 'chrome_text_scale_harness.dart';

/// Pane width used for the fixed-pane case. It is also
/// [PrismTokens.contentMaxWidth], the width every content-primary screen clamps
/// its body to, so this is the real shape of a clamped page.
const double _paneWidth = PrismTokens.contentMaxWidth;

class _Calls {
  int count = 0;
}

class _CountingBar extends StatelessWidget
    implements PreferredSizeWidget, PrismScaledHeight {
  const _CountingBar({required this.calls});

  final _Calls calls;

  @override
  Size get preferredSize => const Size.fromHeight(PrismTokens.topBarHeight);

  @override
  double preferredHeightFor(BuildContext context, {double? availableWidth}) {
    calls.count += 1;
    return PrismTokens.topBarHeight +
        MediaQuery.textScalerOf(context).scale(10) +
        (availableWidth ?? 0) / 100000;
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(child: Center(child: Text('Counting bar')));
}

Widget _list({int count = 40}) => ListView.builder(
  itemCount: count,
  itemBuilder: (context, index) =>
      SizedBox(height: 48, child: Text('Row $index')),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadChromeFonts();
  });

  testWidgets(
    'a fixed pane re-measures when the window crosses the desktop breakpoint',
    (tester) async {
      useWindow(tester, const Size(900, 700));
      const title = 'Fronting schedule today';
      const subtitle = '12 headmates';
      // One instance for both frames: neither theme, scaler nor child changes.
      const bar = PrismTopBar(title: title, subtitle: subtitle);

      Widget page() => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: _paneWidth,
          child: PrismPageScaffold(topBar: bar, body: _list()),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(child: chromeApp(page(), system: 2.25, app: 1.5)),
      );
      await tester.pumpAndSettle();
      final wideBar = tester.getRect(find.byType(PrismTopBar));
      final wideBand = pinnedBandHeight(tester);
      expectNoLayoutException(tester, 'fixed pane, 900dp window');
      expect(
        wideBand,
        closeTo(wideBar.height, 0.5),
        reason: 'the band is the bar before the crossing',
      );

      // Same pane (720dp inside a 760dp window), same child instance, same theme
      // and scaler: only the window width crosses 768, so the title goes from the
      // 18pt desktop style to the 22pt one and the bar needs more room.
      useWindow(tester, const Size(760, 700));
      await tester.pumpAndSettle();

      final narrowBar = tester.getRect(find.byType(PrismTopBar));
      final narrowBand = pinnedBandHeight(tester);
      expect(
        narrowBar.height,
        greaterThan(wideBar.height + 0.5),
        reason:
            'the 22pt title needs more room than the 18pt one '
            '(${narrowBar.height} vs ${wideBar.height})',
      );
      expect(
        narrowBand,
        closeTo(narrowBar.height, 0.5),
        reason:
            'after the window crosses the breakpoint the band must follow the '
            'bar ($narrowBand vs ${narrowBar.height}); a cached extent from the '
            'other style is stale',
      );
      expectFullSizeText(
        tester,
        title,
        label: 'fixed pane after the crossing',
        container: narrowBar,
      );
      expectFullSizeText(
        tester,
        subtitle,
        label: 'fixed pane after the crossing (subtitle)',
        container: narrowBar,
      );
      expectNoLayoutException(tester, 'fixed pane, 760dp window');
    },
  );

  testWidgets(
    'a changed sliver width re-measures the bar at a constant window',
    (tester) async {
      useWindow(tester, const Size(900, 700));
      final calls = _Calls();
      final bar = _CountingBar(calls: calls);

      Widget page(double paneWidth) => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: paneWidth,
          child: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverPinnedTopBar(child: bar),
                SliverList.builder(
                  itemCount: 40,
                  itemBuilder: (context, index) =>
                      SizedBox(height: 48, child: Text('Row $index')),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(child: chromeApp(page(700), system: 1.0, app: 1.0)),
      );
      await tester.pumpAndSettle();
      final atSevenHundred = calls.count;
      expect(atSevenHundred, greaterThan(0));

      await tester.pumpWidget(
        ProviderScope(child: chromeApp(page(800), system: 1.0, app: 1.0)),
      );
      await tester.pumpAndSettle();
      expect(
        calls.count,
        greaterThan(atSevenHundred),
        reason: 'a new cross-axis width is a cache key and must re-measure',
      );
    },
  );
}
