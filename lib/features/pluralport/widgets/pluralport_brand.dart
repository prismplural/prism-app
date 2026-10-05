import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

String _variant(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light';

class PluralPortIcon extends StatelessWidget {
  const PluralPortIcon({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TintedGlassSurface.circle(
      size: size,
      tint: isDark ? const Color(0xFFD4A852) : const Color(0xFF9C7426),
      child: Image.asset(
        'assets/branding/pluralport/icon-${isDark ? 'white' : 'black'}.png',
        width: size / 2,
        height: size / 2,
        excludeFromSemantics: true,
      ),
    );
  }
}

class PluralPortLogo extends StatelessWidget {
  const PluralPortLogo({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    label: 'PluralPort',
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Image.asset(
            'assets/branding/pluralport/logo-${_variant(context)}.png',
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ),
      ),
    ),
  );
}
