import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/widgets/chat_message_text.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_widgets.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';

void main() {
  const probes = [
    _EmojiProbe('ordinary emoji', '✨', wantsSymbolFallback: false),
    _EmojiProbe(
      'emoji presentation selector',
      '⌛️',
      wantsSymbolFallback: false,
    ),
    _EmojiProbe('skin tone sequence', '👍🏽', wantsSymbolFallback: false),
    _EmojiProbe('zwj sequence', '👩‍💻', wantsSymbolFallback: false),
    _EmojiProbe('flag sequence', '🇨🇷', wantsSymbolFallback: false),
    _EmojiProbe('keycap sequence', '1️⃣', wantsSymbolFallback: false),
    _EmojiProbe('text presentation selector', '⌛︎', wantsSymbolFallback: true),
    _EmojiProbe('text arrow selector', '↔︎', wantsSymbolFallback: true),
  ];

  group('plain app text', () {
    for (final probe in probes) {
      testWidgets('${probe.name} does not inherit symbol fallback globally', (
        tester,
      ) async {
        await tester.pumpWidget(_wrap(Text(probe.text)));

        _expectSymbolFallback(
          _fontFamilyFallbackForText(tester, probe.text),
          false,
        );
      });
    }
  });

  final scopedSurfaces = <_Surface>[
    _Surface('markdown', (text) => MarkdownText(data: text)),
    const _Surface('custom field inline markdown', FieldInlineMarkdownText.new),
    _Surface(
      'chat message text',
      (text) => ChatMessageText(
        content: text,
        authorMap: null,
        baseStyle: const TextStyle(fontSize: 16),
        defaultColor: Colors.white,
      ),
    ),
    _Surface(
      'member avatar emoji',
      (text) => MemberAvatar.centeredEmoji(text, fontSize: 24),
    ),
    _Surface(
      'emoji picker selected value',
      (text) => PrismEmojiPicker(emoji: text, onSelected: _ignoreSelected),
    ),
  ];

  for (final surface in scopedSurfaces) {
    group(surface.name, () {
      for (final probe in probes) {
        testWidgets('${probe.name} fallback is scoped to FE0E', (tester) async {
          await tester.pumpWidget(_wrap(surface.build(probe.text)));

          _expectSymbolFallback(
            _fontFamilyFallbackForText(tester, probe.text),
            probe.wantsSymbolFallback,
          );
        });
      }
    });
  }

  testWidgets('markdown numeric entity requests text presentation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const MarkdownText(data: '&#x231b;&#xFE0E;')),
    );

    _expectSymbolFallback(_fontFamilyFallbackForText(tester, '⌛︎'), true);
  });
}

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void _ignoreSelected(String _) {}

void _expectSymbolFallback(List<String>? fallback, bool expected) {
  if (expected) {
    expect(fallback, contains('Noto Sans Symbols'));
  } else {
    expect(fallback ?? const <String>[], isNot(contains('Noto Sans Symbols')));
  }
}

List<String>? _fontFamilyFallbackForText(WidgetTester tester, String text) {
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    final plainText = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (!plainText.contains(text)) continue;

    final span = widget.textSpan;
    if (span is TextSpan) {
      return _spanFontFamilyFallback(span, text) ??
          widget.style?.fontFamilyFallback ??
          span.style?.fontFamilyFallback;
    }
    return widget.style?.fontFamilyFallback;
  }
  return null;
}

List<String>? _spanFontFamilyFallback(
  TextSpan span,
  String text, [
  TextStyle? inheritedStyle,
]) {
  final style =
      inheritedStyle?.merge(span.style) ?? span.style ?? inheritedStyle;
  if ((span.text ?? '').contains(text)) return style?.fontFamilyFallback;

  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) {
      final result = _spanFontFamilyFallback(child, text, style);
      if (result != null) return result;
    }
  }
  return null;
}

class _EmojiProbe {
  const _EmojiProbe(this.name, this.text, {required this.wantsSymbolFallback});

  final String name;
  final String text;
  final bool wantsSymbolFallback;
}

class _Surface {
  const _Surface(this.name, this.build);

  final String name;
  final Widget Function(String text) build;
}
