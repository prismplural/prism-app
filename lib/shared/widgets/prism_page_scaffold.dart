import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';

/// Shared page scaffold for Prism screens with predictable padding and slots.
///
/// When [topBar] is provided the body is placed inside a [NestedScrollView]
/// whose header is [SliverPinnedTopBar]. The inner body scroll drives the
/// outer sliver, so content scrolls behind the bar exactly like the tab
/// screens — same gradient, same behaviour.
///
/// When [bottomFade] is true (default), a gradient mirrors the top-bar fade
/// just above the floating nav bar, so scrolling content fades into the
/// scaffold background instead of meeting the bar at a hard edge.
class PrismPageScaffold extends StatelessWidget {
  const PrismPageScaffold({
    super.key,
    required this.body,
    this.topBar,
    this.backgroundColor,
    this.bodyPadding = PrismTokens.pagePadding,
    this.extendBody = false,
    this.bottomBar,
    this.floatingActionButton,
    this.resizeToAvoidBottomInset,
    this.safeAreaBottom = true,
    this.bottomFade = true,
    this.bottomFadeHeight = 24,
  });

  final Widget body;
  final PreferredSizeWidget? topBar;
  final Color? backgroundColor;
  final EdgeInsets bodyPadding;
  final bool extendBody;
  final Widget? bottomBar;
  final Widget? floatingActionButton;
  final bool? resizeToAvoidBottomInset;
  final bool safeAreaBottom;
  final bool bottomFade;
  final double bottomFadeHeight;

  @override
  Widget build(BuildContext context) {
    final paddedBody = Padding(
      padding: bodyPadding,
      child: safeAreaBottom ? SafeArea(top: false, child: body) : body,
    );

    Widget scaffoldBody = topBar != null
        ? NestedScrollView(
            headerSliverBuilder: (_, _) => [
              SliverPinnedTopBar(child: topBar!),
            ],
            body: paddedBody,
          )
        : paddedBody;

    if (bottomFade) {
      final scaffoldBg =
          backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;
      scaffoldBody = Stack(
        children: [
          scaffoldBody,
          Positioned(
            left: 0,
            right: 0,
            bottom: NavBarInset.of(context),
            height: bottomFadeHeight,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scaffoldBg.withValues(alpha: 0),
                      scaffoldBg,
                      scaffoldBg,
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      extendBody: extendBody,
      body: scaffoldBody,
      bottomNavigationBar: bottomBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
