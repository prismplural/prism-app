import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// Determines whether the layout should use desktop mode, with hysteresis
/// to prevent oscillation near the breakpoint.
///
/// Switches to desktop at [PrismTokens.desktopBreakpoint] (768px),
/// back to mobile at [PrismTokens.desktopBreakpointOff] (720px).
/// Widths in the dead zone (720–768) retain the current mode.
bool shouldBeDesktop(double width, {required bool currentlyDesktop}) {
  if (currentlyDesktop) {
    return width >= PrismTokens.desktopBreakpointOff;
  } else {
    return width >= PrismTokens.desktopBreakpoint;
  }
}
