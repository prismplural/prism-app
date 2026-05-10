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
}

List<String> _plainTextWidgets(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
      .where((text) => text.isNotEmpty)
      .toList();
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
