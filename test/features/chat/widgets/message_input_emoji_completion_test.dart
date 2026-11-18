import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/chat/widgets/emoji_name_completion_overlay.dart';
import 'package:prism_plurality/features/chat/widgets/mention_overlay.dart';
import 'package:prism_plurality/features/chat/widgets/message_input.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

class _FixedSpeakingAsNotifier extends SpeakingAsNotifier {
  _FixedSpeakingAsNotifier(this.memberId);

  final String? memberId;

  @override
  String? build() => memberId;
}

/// Records what the composer sent without touching repositories.
class _RecordingChatNotifier extends ChatNotifier {
  final sentContents = <String>[];

  @override
  Future<String> sendMessage({
    required String conversationId,
    required String content,
    required String authorId,
    String? messageId,
    String? replyToId,
    String? replyToAuthorId,
    String? replyToContent,
  }) async {
    sentContents.add(content);
    return 'message-id-${sentContents.length}';
  }
}

/// Keeps one send in flight so the composer's busy state can be observed.
class _PendingChatNotifier extends ChatNotifier {
  final sentContents = <String>[];
  final release = Completer<void>();

  @override
  Future<String> sendMessage({
    required String conversationId,
    required String content,
    required String authorId,
    String? messageId,
    String? replyToId,
    String? replyToAuthorId,
    String? replyToContent,
  }) async {
    sentContents.add(content);
    await release.future;
    return 'message-id-${sentContents.length}';
  }
}

void main() {
  const aliceId = '00000000-0000-0000-0000-000000000001';
  const bobId = '00000000-0000-0000-0000-000000000002';

  final alice = Member(
    id: aliceId,
    name: 'Alice',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
  );
  final bob = Member(
    id: bobId,
    name: 'Bob',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
  );
  final conversation = Conversation(
    id: 'conv-1',
    participantIds: const [aliceId, bobId],
    createdAt: DateTime(2025, 1, 1),
    lastActivityAt: DateTime(2025, 1, 1),
    isDirectMessage: false,
  );

  Widget buildSubject({
    ChatNotifier Function()? chatNotifierFactory,
    double textScale = 1,
    ComposerDraftCache? draftCache,
  }) {
    return ProviderScope(
      overrides: [
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
        gifServiceConfigProvider.overrideWith(
          (ref) async => const GifServiceConfig.disabled(),
        ),
        speakingAsProvider.overrideWith(
          () => _FixedSpeakingAsNotifier(aliceId),
        ),
        activeMembersProvider.overrideWith((ref) => Stream.value([alice, bob])),
        allGroupsProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroup>[]),
        ),
        allGroupEntriesProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroupEntry>[]),
        ),
        conversationByIdProvider(
          'conv-1',
        ).overrideWith((ref) => Stream.value(conversation)),
        if (chatNotifierFactory != null)
          chatNotifierProvider.overrideWith(chatNotifierFactory),
        if (draftCache != null)
          composerDraftCacheProvider.overrideWithValue(draftCache),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        // MaterialApp.builder is above Navigator and its Overlay, so popup
        // content sees the same text scale as the composer itself.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageInput(conversationId: 'conv-1'),
          ),
        ),
      ),
    );
  }

  final emojiSurface = find.byKey(EmojiNameCompletionOverlay.surfaceKey);

  Finder emojiRow(String label) =>
      find.descendant(of: emojiSurface, matching: find.text(label));

  TextEditingController controllerOf(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!;

  String composerText(WidgetTester tester) => controllerOf(tester).text;

  Future<void> setCaret(WidgetTester tester, int offset) async {
    controllerOf(tester).selection = TextSelection.collapsed(offset: offset);
    await tester.pumpAndSettle();
  }

  testWidgets('typing a colon prefix opens matches and a tap inserts one', (
    tester,
  ) async {
    final notifier = _RecordingChatNotifier();

    await tester.pumpWidget(buildSubject(chatNotifierFactory: () => notifier));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hi :sunflower');
    await tester.pumpAndSettle();

    expect(emojiSurface, findsOneWidget);
    expect(emojiRow('sunflower'), findsOneWidget);
    expect(find.text('🌻'), findsOneWidget);

    await tester.tap(emojiRow('sunflower'));
    await tester.pumpAndSettle();

    expect(composerText(tester), 'hi 🌻');
    expect(emojiSurface, findsNothing);
    expect(notifier.sentContents, isEmpty);
  });

  testWidgets('a bare colon and an unmatched prefix leave no overlay', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), ':');
    await tester.pumpAndSettle();
    expect(emojiSurface, findsNothing);

    await tester.enterText(find.byType(TextField), ':zzzznotanemoji');
    await tester.pumpAndSettle();
    expect(emojiSurface, findsNothing);
  });

  testWidgets('URL schemes, clock times and code do not open the popup', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    for (final draft in [
      'https://example.com/sun',
      'meet at 12:30',
      'a:sun',
      '::sun',
    ]) {
      await tester.enterText(find.byType(TextField), draft);
      await tester.pumpAndSettle();
      expect(emojiSurface, findsNothing, reason: draft);
    }

    // Inside an inline code span, even with the caret at the token end.
    await tester.enterText(find.byType(TextField), '`:sun`');
    await tester.pumpAndSettle();
    expect(emojiSurface, findsNothing);
    await setCaret(tester, 5);
    expect(emojiSurface, findsNothing);

    // Inside a fenced block.
    await tester.enterText(find.byType(TextField), '```\n:sun');
    await tester.pumpAndSettle();
    expect(emojiSurface, findsNothing);
  });

  testWidgets('editing the prefix updates the matches and closes cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), ':sun');
    await tester.pumpAndSettle();
    expect(emojiRow('sunflower'), findsOneWidget);
    expect(emojiRow('sunset'), findsOneWidget);

    // Deleting the last character narrows the list.
    await tester.enterText(find.byType(TextField), ':sunf');
    await tester.pumpAndSettle();
    expect(emojiRow('sunflower'), findsOneWidget);
    expect(emojiRow('sunset'), findsNothing);

    // A terminator closes the token.
    await tester.enterText(find.byType(TextField), ':sunf ');
    await tester.pumpAndSettle();
    expect(emojiSurface, findsNothing);

    // Deleting the whole token closes it too.
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(emojiSurface, findsNothing);
  });

  testWidgets('insertion in the middle of the draft keeps the rest of it', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello :sunflower world');
    await tester.pumpAndSettle();
    expect(emojiSurface, findsNothing);

    await setCaret(tester, 16);
    expect(emojiSurface, findsOneWidget);

    await tester.tap(emojiRow('sunflower'));
    await tester.pumpAndSettle();

    expect(composerText(tester), 'hello 🌻 world');
    expect(controllerOf(tester).selection.baseOffset, 8);
    expect(emojiSurface, findsNothing);
  });

  testWidgets('a caret inside the token does not open the popup', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hi :sunflower');
    await tester.pumpAndSettle();
    expect(emojiSurface, findsOneWidget);

    await setCaret(tester, 8);
    expect(emojiSurface, findsNothing);
  });

  testWidgets('mention completion keeps priority over emoji completion', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '@A');
    await tester.pumpAndSettle();
    expect(find.byType(MentionOverlay), findsOneWidget);
    expect(emojiSurface, findsNothing);

    await tester.enterText(find.byType(TextField), ':sun');
    await tester.pumpAndSettle();
    expect(find.byType(MentionOverlay), findsNothing);
    expect(emojiSurface, findsOneWidget);

    await tester.tap(emojiRow('sun'));
    await tester.pumpAndSettle();
    expect(composerText(tester), '☀️');
  });

  testWidgets('an active IME composition does not open the popup', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    controllerOf(tester).value = const TextEditingValue(
      text: ':sun',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 0, end: 4),
    );
    await tester.pumpAndSettle();
    expect(emojiSurface, findsNothing);

    // The same text without a composition opens normally.
    controllerOf(tester).value = const TextEditingValue(
      text: ':sun',
      selection: TextSelection.collapsed(offset: 4),
    );
    await tester.pumpAndSettle();
    expect(emojiSurface, findsOneWidget);
  });

  testWidgets('member mentions and formatting survive an emoji insertion', (
    tester,
  ) async {
    final notifier = _RecordingChatNotifier();

    await tester.pumpWidget(buildSubject(chatNotifierFactory: () => notifier));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '@[$aliceId] **hi** :sunflower',
    );
    await tester.pumpAndSettle();
    expect(emojiSurface, findsOneWidget);

    await tester.tap(emojiRow('sunflower'));
    await tester.pumpAndSettle();

    expect(composerText(tester), '@[$aliceId] **hi** 🌻');

    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pumpAndSettle();

    expect(notifier.sentContents, ['@[$aliceId] **hi** 🌻']);
    expect(composerText(tester), '');
  });

  testWidgets('the popup stays hidden and sends stay single while busy', (
    tester,
  ) async {
    final notifier = _PendingChatNotifier();

    await tester.pumpWidget(buildSubject(chatNotifierFactory: () => notifier));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), ':sunflower');
    await tester.pumpAndSettle();
    expect(emojiSurface, findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();

    // One send is in flight; typing another token must not open the popup.
    expect(notifier.sentContents, [':sunflower']);
    await tester.enterText(find.byType(TextField), ':sun');
    await tester.pumpAndSettle();
    expect(emojiSurface, findsNothing);

    notifier.release.complete();
    await tester.pumpAndSettle();

    expect(notifier.sentContents, [':sunflower']);
  });

  testWidgets('large text scale on a narrow window keeps the popup usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildSubject(textScale: 2));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), ':sun');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(emojiSurface, findsOneWidget);

    expect(
      MediaQuery.textScalerOf(tester.element(emojiSurface)).scale(14),
      28,
      reason: 'The actual popup, not only the route, must see 2x scaling',
    );
    final surface = tester.getRect(emojiSurface);
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(surface.width, lessThanOrEqualTo(screenWidth));
    expect(surface.left, greaterThanOrEqualTo(0));
    expect(surface.right, lessThanOrEqualTo(screenWidth));
    // The popup sits above the field, never over it.
    expect(
      surface.bottom,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy),
    );

    await tester.tap(emojiRow('sun'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(composerText(tester), '☀️');
  });

  testWidgets('insertion preserves surrounding flag and ZWJ sequences', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();
    const prefix = '👩🏽‍💻 🇨🇦';
    const suffix = ' 🇳🇿 👩‍👩‍👧‍👦';
    const token = ':sunflower';
    const draft = '$prefix $token$suffix';
    await tester.enterText(find.byType(TextField), draft);
    await setCaret(tester, prefix.length + 1 + token.length);
    expect(emojiSurface, findsOneWidget);
    await tester.tap(emojiRow('sunflower'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(composerText(tester), '$prefix 🌻$suffix');
    expect(
      controllerOf(tester).selection,
      const TextSelection.collapsed(offset: prefix.length + 1 + '🌻'.length),
    );
  });

  testWidgets('inserted emoji and cursor survive the draft cache round trip', (
    tester,
  ) async {
    final cache = ComposerDraftCache();
    await tester.pumpWidget(buildSubject(draftCache: cache));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hi :sunflower');
    await tester.pumpAndSettle();
    await tester.tap(emojiRow('sunflower'));
    await tester.pumpAndSettle();
    final inserted = controllerOf(tester).value;
    expect(inserted.text, 'hi 🌻');
    expect(cache.read('conv-1'), inserted);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildSubject(draftCache: cache));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controllerOf(tester).value, inserted);
    expect(emojiSurface, findsNothing);
    expect(cache.read('conv-1'), inserted);
  });

  testWidgets('a restored unfinished token keeps its text and selection', (
    tester,
  ) async {
    const saved = TextEditingValue(
      text: 'unsent :sun',
      selection: TextSelection.collapsed(offset: 11),
    );
    final cache = ComposerDraftCache()..write('conv-1', saved);
    await tester.pumpWidget(buildSubject(draftCache: cache));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controllerOf(tester).value, saved);
    expect(cache.read('conv-1'), saved);
  });

  testWidgets(
    'parse budget hides only suggestions and long plain text completes',
    (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      final sensitive = '` ${'x' * 2200} :sunflower';
      await tester.enterText(find.byType(TextField), sensitive);
      await tester.pumpAndSettle();
      expect(emojiSurface, findsNothing);
      expect(composerText(tester), sensitive);
      expect(controllerOf(tester).selection.baseOffset, sensitive.length);
      final plain = '${'x' * 2200} :sunflower';
      await tester.enterText(find.byType(TextField), plain);
      await tester.pumpAndSettle();
      expect(emojiSurface, findsOneWidget);
      await tester.tap(emojiRow('sunflower'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(composerText(tester), '${'x' * 2200} 🌻');
    },
  );

  group('desktop keyboard', () {
    testWidgets('Enter selects the highlighted emoji and does not send', (
      tester,
    ) async {
      final notifier = _RecordingChatNotifier();

      await _withDesktopPlatform(() async {
        await tester.pumpWidget(
          buildSubject(chatNotifierFactory: () => notifier),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), ':sunflower');
        await tester.pumpAndSettle();
        expect(emojiSurface, findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(composerText(tester), '🌻');
        expect(emojiSurface, findsNothing);
        expect(notifier.sentContents, isEmpty);
      });
    });

    testWidgets('arrow keys move the highlight before Enter selects', (
      tester,
    ) async {
      await _withDesktopPlatform(() async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), ':sun');
        await tester.pumpAndSettle();
        expect(emojiRow('sun'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        // The second match for `sun` is sunset, not the exact `sun` row.
        expect(composerText(tester), '🌇');
      });
    });

    testWidgets('Escape closes the popup and keeps the typed token', (
      tester,
    ) async {
      final notifier = _RecordingChatNotifier();

      await _withDesktopPlatform(() async {
        await tester.pumpWidget(
          buildSubject(chatNotifierFactory: () => notifier),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'hi :sunflower');
        await tester.pumpAndSettle();
        expect(emojiSurface, findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(emojiSurface, findsNothing);
        expect(composerText(tester), 'hi :sunflower');
        expect(notifier.sentContents, isEmpty);

        // With the popup closed, Enter is the normal send path again.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(notifier.sentContents, ['hi :sunflower']);
      });
    });
  });

  group('3.375x narrow composer', () {
    testWidgets('keeps the popup usable and inserts the chosen emoji', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildSubject(textScale: 3.375));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), ':sun');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(emojiSurface, findsOneWidget);

      expect(
        MediaQuery.textScalerOf(tester.element(emojiSurface)).scale(14),
        47.25,
        reason: 'The real popup, not only the route, must see 3.375x scaling.',
      );

      final surface = tester.getRect(emojiSurface);
      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(surface.left, greaterThanOrEqualTo(0));
      expect(surface.right, lessThanOrEqualTo(screenWidth));
      expect(surface.top, greaterThanOrEqualTo(0));
      expect(
        surface.bottom,
        lessThanOrEqualTo(screenHeight),
        reason: 'A 3.375x popup must not paint past the bottom of the window.',
      );
      expect(
        surface.bottom,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy),
        reason: 'The popup sits above the field, never over it.',
      );

      // The popup scrolls its own rows, so the chosen row can be below the
      // fold at this scale; bring it into view before tapping.
      await tester.ensureVisible(emojiRow('sun'));
      await tester.pumpAndSettle();
      final scrolledSurface = tester.getRect(emojiSurface);
      expect(
        scrolledSurface.bottom,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy),
        reason: 'Scrolling inside the popup must not move it over the field.',
      );

      await tester.tap(emojiRow('sun'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(composerText(tester), '☀️');
    });
  });
}

/// Run [body] with the desktop platform override in place.
///
/// The override has to be cleared **inside** the test body: the binding's
/// `debugAssertAllFoundationVarsUnset` invariant runs when the body returns, so
/// resetting it in `tearDown` is too late and fails the test.
Future<void> _withDesktopPlatform(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
