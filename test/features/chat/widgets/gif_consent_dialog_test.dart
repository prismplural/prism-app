import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/chat/widgets/gif_consent_dialog.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

Widget _buildTestApp({required ValueChanged<bool> onResult}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => _ConversationList(onResult: onResult),
        ),
      ),
    ),
  );
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({required this.onResult});

  final ValueChanged<bool> onResult;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Conversation list'),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _ChatScreen(onResult: onResult),
              ),
            );
          },
          child: const Text('Open chat'),
        ),
      ],
    );
  }
}

class _ChatScreen extends StatelessWidget {
  const _ChatScreen({required this.onResult});

  final ValueChanged<bool> onResult;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Chat screen'),
        ElevatedButton(
          onPressed: () async {
            final result = await GifConsentDialog.show(context);
            onResult(result);
          },
          child: const Text('Open GIF consent'),
        ),
      ],
    );
  }
}

void main() {
  testWidgets('enable closes dialog without popping nested chat route', (
    tester,
  ) async {
    bool? result;
    await tester.binding.setSurfaceSize(const Size(600, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildTestApp(onResult: (value) => result = value));

    await tester.tap(find.text('Open chat'));
    await tester.pumpAndSettle();
    expect(find.text('Chat screen'), findsOneWidget);

    await tester.tap(find.text('Open GIF consent'));
    await tester.pumpAndSettle();
    expect(find.byType(GifConsentDialog), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'Dialog body should scroll instead of overflowing',
    );

    await tester.tap(find.widgetWithText(PrismButton, 'Enable GIFs'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.byType(GifConsentDialog), findsNothing);
    expect(find.text('Chat screen'), findsOneWidget);
    expect(find.text('Conversation list'), findsNothing);
  });

  testWidgets('decline closes dialog without popping nested chat route', (
    tester,
  ) async {
    bool? result;
    await tester.binding.setSurfaceSize(const Size(600, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildTestApp(onResult: (value) => result = value));

    await tester.tap(find.text('Open chat'));
    await tester.pumpAndSettle();
    expect(find.text('Chat screen'), findsOneWidget);

    await tester.tap(find.text('Open GIF consent'));
    await tester.pumpAndSettle();
    expect(find.byType(GifConsentDialog), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'Dialog body should scroll instead of overflowing',
    );

    await tester.tap(find.widgetWithText(PrismButton, 'No Thanks'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.byType(GifConsentDialog), findsNothing);
    expect(find.text('Chat screen'), findsOneWidget);
    expect(find.text('Conversation list'), findsNothing);
  });
}
