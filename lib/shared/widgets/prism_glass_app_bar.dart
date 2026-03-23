import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// A centered app bar layout intended to pair with Prism glass controls.
class PrismGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PrismGlassAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.height = 66,
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
  Widget build(BuildContext context) {
    return PrismTopBar(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: trailing,
      height: height,
      horizontalPadding: EdgeInsets.symmetric(horizontal: horizontalPadding),
    );
  }
}
