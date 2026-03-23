import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// Shared page scaffold for Prism screens with predictable padding and slots.
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
    final content = Padding(
      padding: bodyPadding,
      child: safeAreaBottom ? SafeArea(top: false, child: body) : body,
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      extendBody: extendBody,
      appBar: topBar,
      body: content,
      bottomNavigationBar: bottomBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
