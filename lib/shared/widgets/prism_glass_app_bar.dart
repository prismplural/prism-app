import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// A centered app bar layout intended to pair with Prism glass controls.
///
/// [height] is the minimum (66dp by default). Callers that place this bar in a
/// slot which reserves a fixed extent — `Scaffold.appBar` is the only such slot in
/// Prism — must declare the height they want with [preferredHeightFor]; inside a
/// [SliverPinnedTopBar] the sliver asks for it instead and no caller wiring is
/// needed.
class PrismGlassAppBar extends StatelessWidget
    implements PreferredSizeWidget, PrismScaledHeight {
  const PrismGlassAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.height = PrismTokens.topBarHeight,
    this.horizontalPadding = 12,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final double height;
  final double horizontalPadding;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  double preferredHeightFor(BuildContext context, {double? availableWidth}) {
    return _bar().preferredHeightFor(context, availableWidth: availableWidth);
  }

  PrismTopBar _bar() {
    return PrismTopBar(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: trailing,
      height: height,
      horizontalPadding: EdgeInsets.symmetric(horizontal: horizontalPadding),
    );
  }

  @override
  Widget build(BuildContext context) => _bar();
}
