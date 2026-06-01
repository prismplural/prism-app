import 'package:flutter/material.dart';

const List<String> textPresentationFontFallback = [
  'Apple Symbols',
  'Segoe UI Symbol',
  'Noto Sans Symbols',
  'Noto Sans Symbols 2',
  'Symbola',
];

final _textPresentationEntityRegex = RegExp(
  r'&#(?:x0*fe0e|0*65038);',
  caseSensitive: false,
);

bool requestsTextPresentation(String text) {
  return text.contains('\uFE0E') || _textPresentationEntityRegex.hasMatch(text);
}

TextStyle? nullableTextStyleForTextPresentation(TextStyle? style, String text) {
  if (!requestsTextPresentation(text)) return style;
  return textStyleForTextPresentation(style ?? const TextStyle(), text);
}

TextStyle textStyleForTextPresentation(TextStyle style, String text) {
  if (!requestsTextPresentation(text)) return style;
  return style.copyWith(
    fontFamilyFallback: textPresentationFallback(style.fontFamilyFallback),
  );
}

List<String> textPresentationFallback(List<String>? existing) {
  final seen = <String>{};
  return [
    for (final family in [...textPresentationFontFallback, ...?existing])
      if (seen.add(family)) family,
  ];
}
