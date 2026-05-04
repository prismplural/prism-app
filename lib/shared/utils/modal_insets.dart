import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Bottom inset for modal surfaces that must clear both the keyboard and the
/// persistent system navigation area on Android three-button navigation.
///
/// Use this for sheets, modal toolbars, and popups that own their bottom
/// padding. Avoid adding it inside a bottom [SafeArea] unless the extra
/// breathing room is intentional.
double modalBottomInsetOf(BuildContext context) {
  final mediaQuery = MediaQuery.maybeOf(context);
  if (mediaQuery == null) return 0;

  return math.max(mediaQuery.viewInsets.bottom, mediaQuery.viewPadding.bottom);
}
