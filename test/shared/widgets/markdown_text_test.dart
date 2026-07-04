import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';

void main() {
  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, null);
  });

  testWidgets('blockquote lines preserve authored newlines', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(data: '> ▹ first line\n> ▹ second line'),
        ),
      ),
    );

    expect(_plainTextWidgets(tester), contains('▹ first line\n▹ second line'));
  });

  testWidgets('tables inside blockquotes render as tables', (tester) async {
    const markdown =
        '> | left | right |\n'
        '> | - | - |\n'
        '> | moon | water |';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: MarkdownText(data: markdown)),
      ),
    );

    expect(find.byType(Table), findsOneWidget);
    expect(_plainTextWidgets(tester).join('\n'), contains('moon'));
    expect(_hasDecoratedBlockquote(tester), isTrue);
  });

  testWidgets('tables after quoted blank lines stay inside blockquotes', (
    tester,
  ) async {
    const markdown =
        '> likes\n'
        '>\n'
        '> | left | right |\n'
        '> | - | - |\n'
        '> | moon | water |';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: MarkdownText(data: markdown)),
      ),
    );

    expect(find.byType(Table), findsOneWidget);
    expect(_plainTextWidgets(tester).join('\n'), contains('likes'));
    expect(_hasDecoratedBlockquote(tester), isTrue);
  });

  testWidgets('numeric HTML entities preserve text presentation selectors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: MarkdownText(data: '&#x231b;&#xFE0E;')),
      ),
    );

    final text = _plainTextWidgets(tester).join('\n');
    expect(text, contains('\u231B\uFE0E'));
    expect(text, isNot(contains('&#x231b;')));
    expect(
      _fontFamilyFallbackForText(tester, '\u231B\uFE0E'),
      contains('Noto Sans Symbols'),
    );
  });

  testWidgets('ordinary emoji markdown does not add symbol fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: MarkdownText(data: '✨')),
      ),
    );

    expect(
      _fontFamilyFallbackForText(tester, '✨') ?? const <String>[],
      isNot(contains('Noto Sans Symbols')),
    );
  });

  testWidgets('indented markdown does not become an implicit code block', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: MarkdownText(data: '    **bold**')),
      ),
    );

    final text = _plainTextWidgets(tester).join('\n');
    expect(text, contains('bold'));
    expect(text, isNot(contains('**bold**')));
  });

  testWidgets('indented blockquotes still parse as blockquotes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: MarkdownText(data: '    > **quoted**')),
      ),
    );

    final text = _plainTextWidgets(tester).join('\n');
    expect(text, contains('quoted'));
    expect(text, isNot(contains('> **quoted**')));
  });

  testWidgets('fenced code blocks remain literal', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: MarkdownText(data: '```\n**bold**\n```')),
      ),
    );

    expect(_plainTextWidgets(tester).join('\n'), contains('**bold**'));
  });

  testWidgets('Simply Plural decorative spacer bios preserve lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: MarkdownText(data: _decorativeSpacerBio)),
      ),
    );

    final text = _plainTextWidgets(tester).join('\n');
    expect(text, contains('ⓘ⠀⠀EXAMPLE⠀.⠀SAMPLE\n'));
    expect(text, contains('†⠀Plain field﹔value\n'));
    expect(text, contains('†⠀Bold field﹔bold value\n'));
    expect(text, isNot(contains('**Bold field﹔bold value**')));
  });

  testWidgets('decorative spacer and ASCII indented markdown coexist', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(data: _mixedSpacerAndAsciiIndentBio),
        ),
      ),
    );

    final text = _plainTextWidgets(tester).join('\n');
    expect(text, contains('ASCII indent bold\n'));
    expect(text, contains('UNICODE spacer bold\n'));
    expect(text, contains('ASCII quote'));
    expect(text, isNot(contains('**ASCII indent bold**')));
    expect(text, isNot(contains('> **ASCII quote**')));
  });

  testWidgets('paragraph after a list does not inherit list indentation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(
            data:
                '## list testing\n\n'
                '- item one\n'
                '- item two\n'
                '- item three\n\n'
                'not a list item',
          ),
        ),
      ),
    );

    final headingLeft = tester.getTopLeft(find.text('list testing')).dx;
    final itemLeft = tester.getTopLeft(find.text('item one')).dx;
    final paragraphLeft = tester.getTopLeft(find.text('not a list item')).dx;

    expect(paragraphLeft, closeTo(headingLeft, 1));
    expect(paragraphLeft, lessThan(itemLeft));
  });

  testWidgets('textAlign applies to formatted paragraphs and subtext', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(
            data: 'Aligned **body**\n\n-# quiet aside',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );

    final body = _richTextContaining(tester, 'Aligned body');
    expect(body.textAlign, TextAlign.center);

    final subtext = _textContaining(tester, 'quiet aside');
    expect(subtext.textAlign, TextAlign.center);
  });

  group('plain line escapes', () {
    test(
      'escape non-punctuation line starts while preserving CommonMark escapes',
      () {
        expect(
          applyPlainLineEscapes(r'\testing **not bold**'),
          r'testing \*\*not bold\*\*',
        );
        expect(
          applyPlainLineEscapes(r'\ hello **not bold**'),
          r'hello \*\*not bold\*\*',
        );
        expect(applyPlainLineEscapes(r'\ ||spoiler||'), r'\|\|spoiler\|\|');
        expect(
          applyPlainLineEscapes(r'\\ hello **not bold**'),
          r'\\ hello \*\*not bold\*\*',
        );
        expect(applyPlainLineEscapes(r'\- item **bold**'), r'\- item **bold**');
        expect(applyPlainLineEscapes(r'\# heading'), r'\# heading');
      },
    );

    testWidgets('leading slash before text renders the line literally', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(data: r'\testing **not bold** [x](url)'),
          ),
        ),
      );

      final text = _plainTextWidgets(tester).join('\n');
      expect(text, contains('testing **not bold** [x](url)'));
      expect(text, isNot(contains(r'\testing')));
    });

    testWidgets('slash-space escapes a punctuation-leading line', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: r'\ ||not hidden||')),
        ),
      );

      expect(_plainTextWidgets(tester).join('\n'), contains('||not hidden||'));
    });

    testWidgets('doubled leading slash renders a literal leading slash', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(data: r'\\ hello **not bold**'),
          ),
        ),
      );

      expect(
        _plainTextWidgets(tester).join('\n'),
        contains(r'\ hello **not bold**'),
      );
    });

    testWidgets('standard punctuation escapes still use CommonMark behavior', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: r'\- item **bold**')),
        ),
      );

      final text = _plainTextWidgets(tester).join('\n');
      expect(text, contains('- item bold'));
      expect(text, isNot(contains(r'\-')));
      expect(text, isNot(contains('**bold**')));
    });

    testWidgets('escaped lines do not absorb adjacent lists', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(
              data:
                  '- before\n\n'
                  r'\literal **middle**'
                  '\n\n- after',
            ),
          ),
        ),
      );

      final beforeLeft = tester.getTopLeft(find.text('before')).dx;
      final middleLeft = tester.getTopLeft(find.text('literal **middle**')).dx;
      final afterLeft = tester.getTopLeft(find.text('after')).dx;

      expect(middleLeft, lessThan(beforeLeft));
      expect(afterLeft, closeTo(beforeLeft, 1));
    });

    testWidgets('escaped lines can sit before and after tables', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(
              data:
                  r'\before **plain**'
                  '\n\n| A | B |\n'
                  '| --- | --- |\n'
                  '| one | two |\n\n'
                  r'\after **plain**',
            ),
          ),
        ),
      );

      final text = _plainTextWidgets(tester).join('\n');
      expect(text, contains('before **plain**'));
      expect(text, contains('A'));
      expect(text, contains('B'));
      expect(text, contains('one'));
      expect(text, contains('two'));
      expect(text, contains('after **plain**'));
      expect(text, isNot(contains('|')));
    });

    testWidgets('plain line escape is line-level, not table-cell-level', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(
              data:
                  '| A | B |\n'
                  '| --- | --- |\n'
                  r'| \testing | **bold** |',
            ),
          ),
        ),
      );

      final text = _plainTextWidgets(tester).join('\n');
      expect(text, contains(r'\testing'));
      expect(text, contains('bold'));
      expect(text, isNot(contains('|')));
    });

    testWidgets('slash-space can escape a would-be table row', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: r'\ | A | **B** |')),
        ),
      );

      expect(_plainTextWidgets(tester).join('\n'), contains('| A | **B** |'));
    });

    testWidgets('escaped lines do not absorb adjacent blockquotes', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(
              data:
                  '> before\n\n'
                  r'\literal **middle**'
                  '\n\n> after',
            ),
          ),
        ),
      );

      final beforeLeft = tester.getTopLeft(find.text('before')).dx;
      final middleLeft = tester.getTopLeft(find.text('literal **middle**')).dx;
      final afterLeft = tester.getTopLeft(find.text('after')).dx;

      expect(middleLeft, lessThan(beforeLeft));
      expect(afterLeft, closeTo(beforeLeft, 1));
    });

    testWidgets('slash-space can escape heading syntax', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: r'\ # plain heading')),
        ),
      );

      expect(_plainTextWidgets(tester).join('\n'), contains('# plain heading'));
      expect(find.text('plain heading'), findsNothing);
    });

    testWidgets('escaped list continuation renders literally inside item', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(
              data:
                  '- item\n'
                  r'  \literal **continuation**',
            ),
          ),
        ),
      );

      final text = _plainTextWidgets(tester).join('\n');
      expect(text, contains('item\nliteral **continuation**'));
    });

    testWidgets('plain escape works before custom spoiler and subtext syntax', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(
              data:
                  r'\ ||not hidden||'
                  '\n'
                  r'\ -# not small',
            ),
          ),
        ),
      );

      final text = _plainTextWidgets(tester).join('\n');
      expect(text, contains('||not hidden||'));
      expect(text, contains('-# not small'));
    });

    testWidgets('plain escapes are not applied inside fenced code blocks', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(
              data:
                  '```\n'
                  r'\testing **still code**'
                  '\n```',
            ),
          ),
        ),
      );

      expect(
        _plainTextWidgets(tester).join('\n'),
        contains(r'\testing **still code**'),
      );
    });
  });

  testWidgets('links flow inside surrounding paragraph text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(
            data:
                '> ▹ It and [Doc](https://example.com) are very close, and '
                'are essentially a [bonded pair](https://example.com/pair)',
          ),
        ),
      ),
    );

    expect(
      _plainTextWidgets(tester),
      contains(
        '▹ It and Doc are very close, and are essentially a bonded pair',
      ),
    );
    expect(find.text('Doc'), findsNothing);
    expect(find.text('bonded pair'), findsNothing);
  });

  testWidgets('links launch non-web schemes except javascript and data', (
    tester,
  ) async {
    final launchedUrls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, (call) async {
          if (call.method == 'launch') {
            final args = call.arguments as Map<Object?, Object?>;
            launchedUrls.add(args['url']! as String);
            return true;
          }
          return false;
        });

    Future<void> tapOnlyLink(String markdown) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MarkdownText(data: markdown)),
        ),
      );
      await tester.tap(find.byType(RichText));
      await tester.pumpAndSettle();
    }

    await tapOnlyLink('[Email](mailto:test@example.com)');
    await tapOnlyLink('[Phone](tel:+15551234567)');
    await tapOnlyLink('[Custom](matrix:u/example:example.com)');
    await tapOnlyLink('[JS](JavaScript:alert(1))');
    await tapOnlyLink('[Data](DATA:text/plain,hello)');
    await tapOnlyLink('[Relative](/relative/path)');

    expect(launchedUrls, [
      'mailto:test@example.com',
      'tel:+15551234567',
      'matrix:u/example:example.com',
    ]);
  });

  testWidgets('`-# small text` renders without the marker at reduced size', (
    tester,
  ) async {
    // Use an explicit fontSize so we can assert the smaller subtext size
    // independent of theme/DefaultTextStyle resolution.
    const baseSize = 16.0;
    const bodyStyle = TextStyle(fontSize: baseSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(
            data: 'normal line\n-# subtle aside',
            baseStyle: bodyStyle,
          ),
        ),
      ),
    );

    final visibleText = _plainTextWidgets(tester).join('\n');
    expect(visibleText, contains('subtle aside'));
    expect(visibleText, isNot(contains('-#')));

    // SubtextBuilder now returns a Text.rich; the size lives on the root
    // TextSpan rather than the Text widget itself.
    final smallText = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere(
          (w) => (w.data ?? w.textSpan?.toPlainText() ?? '') == 'subtle aside',
        );
    final rootStyle = smallText.style ?? smallText.textSpan?.style;
    expect(rootStyle?.fontSize, isNotNull);
    expect(rootStyle!.fontSize, lessThan(baseSize));
  });

  testWidgets('`-#` mid-line is left as literal text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(data: 'tag id -# foo on same line'),
        ),
      ),
    );

    expect(_plainTextWidgets(tester), contains('tag id -# foo on same line'));
  });

  testWidgets('`-#` is ignored when markdown is disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(data: '-# small', enabled: false),
        ),
      ),
    );

    expect(_plainTextWidgets(tester), contains('-# small'));
  });

  testWidgets('`-#` preserves inline bold and italic styling', (tester) async {
    const baseSize = 16.0;
    const bodyStyle = TextStyle(fontSize: baseSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(
            data: '-# normal **bold** and *italic*',
            baseStyle: bodyStyle,
          ),
        ),
      ),
    );

    // The subtext block is rendered as a Text.rich. Find it by checking
    // for the visible content and then walk the TextSpan tree to assert
    // the bold/italic styling survives.
    final richTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where(
          (w) => (w.data ?? w.textSpan?.toPlainText() ?? '').contains('bold'),
        );
    expect(richTexts, isNotEmpty);
    final root = richTexts.first.textSpan!;
    final spans = <InlineSpan>[];
    root.visitChildren((span) {
      spans.add(span);
      return true;
    });
    final boldSpan = spans.firstWhere(
      (s) => (s.toPlainText()).contains('bold'),
    );
    final italicSpan = spans.firstWhere(
      (s) => (s.toPlainText()).contains('italic'),
    );
    expect(boldSpan.style?.fontWeight, FontWeight.bold);
    expect(italicSpan.style?.fontStyle, FontStyle.italic);
    // Smaller than the body size even with inline styling applied.
    expect(boldSpan.style?.fontSize, lessThan(baseSize));
  });

  testWidgets('`-#` attaches a tap recognizer to nested link spans', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(data: '-# see [docs](https://example.com/docs)'),
        ),
      ),
    );

    // Find the subtext Text.rich and walk its TextSpan tree (recursively)
    // for a span whose visible text matches the link label and has a
    // recognizer attached.
    final subtextTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where(
          (w) => (w.data ?? w.textSpan?.toPlainText() ?? '').contains('docs'),
        );
    expect(subtextTexts, isNotEmpty);
    final spans = <InlineSpan>[];
    void collect(InlineSpan span) {
      spans.add(span);
      if (span is TextSpan) {
        for (final child in span.children ?? const <InlineSpan>[]) {
          collect(child);
        }
      }
    }

    collect(subtextTexts.first.textSpan!);
    // The recognizer must live on a LEAF text span (one with non-empty
    // `text`), because Flutter's hit test resolves to the leaf at the tap
    // position. A recognizer attached to a parent wrapper TextSpan with no
    // text is unreachable.
    final tappableLeafSpans = spans
        .whereType<TextSpan>()
        .where(
          (s) =>
              s.recognizer is TapGestureRecognizer &&
              (s.text?.isNotEmpty ?? false),
        )
        .toList();
    expect(
      tappableLeafSpans,
      isNotEmpty,
      reason:
          'recognizer must be on a leaf span with text so hit test reaches it',
    );
    // Sanity check: every leaf with text inside the link label carries the
    // same recognizer instance.
    final recognizers = tappableLeafSpans.map((s) => s.recognizer).toSet();
    expect(recognizers, hasLength(1));
  });

  testWidgets('indented `-#` in a bio still renders as subtext', (
    tester,
  ) async {
    const baseSize = 16.0;
    const bodyStyle = TextStyle(fontSize: baseSize);

    // Discord-style bios often have 4-space leading indentation as visual
    // padding. The normalizer must strip that indent for `-#` lines or
    // the literal marker leaks through.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(
            data: '    -# indented aside',
            baseStyle: bodyStyle,
          ),
        ),
      ),
    );

    final visibleText = _plainTextWidgets(tester).join('\n');
    expect(visibleText, contains('indented aside'));
    expect(visibleText, isNot(contains('-#')));
  });

  testWidgets('consecutive `-#` lines each render without the marker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(data: '-# first aside\n-# second aside'),
        ),
      ),
    );

    final visibleText = _plainTextWidgets(tester).join('\n');
    expect(visibleText, contains('first aside'));
    expect(visibleText, contains('second aside'));
    expect(visibleText, isNot(contains('-#')));
  });

  testWidgets('consecutive `-#` lines keep authored line breaks', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(data: '-# first aside\n-# second aside'),
        ),
      ),
    );

    final subtext = _textContaining(tester, 'first aside');

    expect(
      subtext.data ?? subtext.textSpan?.toPlainText(),
      'first aside\nsecond aside',
    );
  });

  testWidgets('consecutive `-#` parsing stops before normal paragraphs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(data: '-# first aside\nregular text'),
        ),
      ),
    );

    final subtext = _textContaining(tester, 'first aside');
    expect(subtext.data ?? subtext.textSpan?.toPlainText(), 'first aside');
    expect(
      _richTextContaining(tester, 'regular text').text.toPlainText(),
      'regular text',
    );
  });

  testWidgets('blank lines keep `-#` runs as separate subtext blocks', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(data: '-# first aside\n\n-# second aside'),
        ),
      ),
    );

    final first = _textContaining(tester, 'first aside');
    final second = _textContaining(tester, 'second aside');

    expect(first.data ?? first.textSpan?.toPlainText(), 'first aside');
    expect(second.data ?? second.textSpan?.toPlainText(), 'second aside');
  });

  testWidgets('inline formatting spans consecutive `-#` line breaks', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(data: '-# *first aside\n-# second aside*'),
        ),
      ),
    );

    final subtext = _textContaining(tester, 'first aside');
    expect(
      subtext.data ?? subtext.textSpan?.toPlainText(),
      'first aside\nsecond aside',
    );

    final visibleText = <String>[];
    final visibleStyles = <TextStyle?>[];
    void collect(InlineSpan span, [TextStyle? inheritedStyle]) {
      if (span is TextSpan) {
        final style =
            inheritedStyle?.merge(span.style) ?? span.style ?? inheritedStyle;
        final text = span.text;
        if (text != null && text.isNotEmpty) {
          visibleText.add(text);
          visibleStyles.add(style);
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          collect(child, style);
        }
      }
    }

    collect(subtext.textSpan!);
    expect(visibleText.join(), 'first aside\nsecond aside');
    for (var i = 0; i < visibleText.length; i += 1) {
      if (visibleText[i].trim().isEmpty) continue;
      expect(visibleStyles[i]?.fontStyle, FontStyle.italic);
    }
  });

  testWidgets('`-#` inside a list item renders as subtext', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(data: '- item one\n- -# muted item'),
        ),
      ),
    );

    final visibleText = _plainTextWidgets(tester).join('\n');
    expect(visibleText, contains('item one'));
    expect(visibleText, contains('muted item'));
    expect(visibleText, isNot(contains('-#')));
  });

  testWidgets('`-#` inside a blockquote renders as subtext', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: MarkdownText(data: '> -# quoted aside')),
      ),
    );

    final visibleText = _plainTextWidgets(tester).join('\n');
    expect(visibleText, contains('quoted aside'));
    expect(visibleText, isNot(contains('-#')));
  });

  testWidgets('`-#` link actually fires launcher on tap', (tester) async {
    final launchedUrls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, (call) async {
          if (call.method == 'launch') {
            final args = call.arguments as Map<Object?, Object?>;
            launchedUrls.add(args['url']! as String);
            return true;
          }
          return false;
        });

    // Link is the only visible content in the subtext, so tapping the
    // center of the RichText reliably lands on the link's leaf span.
    // If the structural recognizer test ever drifts (e.g. recognizer
    // placed on a no-text wrapper), this behavioral test catches it.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: MarkdownText(data: '-# [docs](https://example.com/docs)'),
        ),
      ),
    );

    await tester.tap(find.byType(RichText).last);
    await tester.pumpAndSettle();
    expect(launchedUrls, contains('https://example.com/docs'));
  });

  testWidgets('task-list checkboxes use Prism dark-mode colors', (
    tester,
  ) async {
    final theme = AppTheme.dark();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: MarkdownText(data: '- [ ] Pending\n- [x] Done'),
        ),
      ),
    );

    final unchecked = tester.widget<Icon>(
      find.byIcon(Icons.check_box_outline_blank),
    );
    final checked = tester.widget<Icon>(find.byIcon(Icons.check_box));

    expect(
      unchecked.color,
      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.92),
    );
    expect(checked.color, theme.colorScheme.primary);
  });

  group('spoilers', () {
    List<double> spoilerOpacities(WidgetTester tester) {
      return tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((w) => w.opacity)
          .toList();
    }

    testWidgets('||spoiler|| renders a hidden pill, not literal pipes', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(data: 'before ||secret|| after'),
          ),
        ),
      );

      // The pipe markers are consumed; the inner text is present but hidden
      // (the hidden layer is opaque, the revealed layer transparent).
      final text = _plainTextWidgets(tester).join('\n');
      expect(text, isNot(contains('||')));
      expect(spoilerOpacities(tester), [1.0, 0.0]);
    });

    testWidgets('tapping a spoiler reveals it', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: '||secret||')),
        ),
      );

      expect(spoilerOpacities(tester), [1.0, 0.0]);
      await tester.tap(find.byType(AnimatedOpacity).first);
      await tester.pumpAndSettle();
      expect(spoilerOpacities(tester), [0.0, 1.0]);
    });

    testWidgets('reveal state resets when the content changes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: '||secret||')),
        ),
      );
      await tester.tap(find.byType(AnimatedOpacity).first);
      await tester.pumpAndSettle();
      expect(spoilerOpacities(tester), [0.0, 1.0]);

      // Same widget slot, new content: the previously revealed spoiler must
      // not carry its revealed state over to the new text.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: '||other||')),
        ),
      );
      await tester.pumpAndSettle();
      expect(spoilerOpacities(tester), [1.0, 0.0]);
    });

    testWidgets('two spoilers in separate blocks reveal independently', (
      tester,
    ) async {
      // Regression: reveal state used to key on the inline parser's
      // block-local offset, so two spoilers at the same offset in different
      // paragraphs collided — revealing one leaked the other.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MarkdownText(data: '||alpha||\n\n||bravo||'),
          ),
        ),
      );
      expect(spoilerOpacities(tester), [1.0, 0.0, 1.0, 0.0]);

      await tester.tap(find.byType(AnimatedOpacity).first);
      await tester.pumpAndSettle();
      // Only the first spoiler reveals; the second stays hidden.
      expect(spoilerOpacities(tester), [0.0, 1.0, 1.0, 0.0]);
    });

    testWidgets('spoiler inside -# subtext does not leak plaintext', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MarkdownText(data: '-# ||topsecret||')),
        ),
      );

      final text = _plainTextWidgets(tester).join('\n');
      expect(text, isNot(contains('topsecret')));
      expect(text, contains('▮'));
    });
  });
}

RichText _richTextContaining(WidgetTester tester, String value) {
  return tester
      .widgetList<RichText>(find.byType(RichText))
      .singleWhere((widget) => widget.text.toPlainText().contains(value));
}

Text _textContaining(WidgetTester tester, String value) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .singleWhere(
        (widget) => (widget.data ?? widget.textSpan?.toPlainText() ?? '')
            .contains(value),
      );
}

List<String> _plainTextWidgets(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
      .where((text) => text.isNotEmpty)
      .toList();
}

bool _hasDecoratedBlockquote(WidgetTester tester) {
  return tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).any((
    decoratedBox,
  ) {
    final decoration = decoratedBox.decoration;
    return decoration is BoxDecoration &&
        decoration.border is Border &&
        (decoration.border as Border).left.width == 3;
  });
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

const _decorativeSpacerBio = '''
⠀**⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯**
⠀ ⠀⠀**ⓘ⠀⠀EXAMPLE⠀.⠀SAMPLE**
⠀**⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯**
⠀⠀†⠀Plain field﹔value
⠀⠀†⠀**Bold field﹔bold value**
⠀⠀†⠀Placeholder﹔placeholder
⠀⠀†⠀Placeholder
⠀⠀†⠀**Another bold field**
⠀⠀†⠀Plain line⠀♡
⠀**⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯**
⠀⠀⠀⠀⠀⠀***⟳⠀Styled label***
⠀**⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯**
⠀⠀†⠀Number﹔label
⠀⠀†⠀**Label﹔connection**
⠀⠀†⠀Code + code﹔friendly note
⠀**⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯**''';

const _mixedSpacerAndAsciiIndentBio = '''
    **ASCII indent bold**
⠀**UNICODE spacer bold**
    > **ASCII quote**''';
