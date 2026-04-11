import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';

/// Shared page scaffold for Prism screens with predictable padding and slots.
///
/// When [topBar] is provided the body is placed inside a [NestedScrollView]
/// whose header is [SliverPinnedTopBar]. The inner body scroll drives the
/// outer sliver, so content scrolls behind the bar exactly like the tab
/// screens — same gradient, same behaviour.
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

  @override
  Widget build(BuildContext context) {
    final paddedBody = Padding(
      padding: bodyPadding,
      child: safeAreaBottom ? SafeArea(top: false, child: body) : body,
    );

    final scaffoldBody = topBar != null
        ? NestedScrollView(
            headerSliverBuilder: (_, _) => [
              SliverPinnedTopBar(child: topBar!),
            ],
            body: paddedBody,
          )
        : paddedBody;

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
