import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/views/create_conversation_sheet.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_checkbox_row.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fake providers
// ─────────────────────────────────────────────────────────────────────────────

class _FakeSpeakingAsNotifier extends SpeakingAsNotifier {
  _FakeSpeakingAsNotifier([this._memberId]);
  final String? _memberId;

  @override
  String? build() => _memberId;
}

class _FakeChatNotifier extends ChatNotifier {
  String? createdTitle;
  String? createdEmoji;
  String? createdCreatorId;
  List<String>? createdParticipantIds;
  String? createdCategoryId;
  bool? createdIsDirectMessage;

  @override
  Future<void> build() async {}

  @override
  Future<Conversation> createGroupConversation({
    required String title,
    String? emoji,
    required String creatorId,
    required List<String> participantIds,
    String? categoryId,
    bool isDirectMessage = false,
  }) async {
    createdTitle = title;
    createdEmoji = emoji;
    createdCreatorId = creatorId;
    createdParticipantIds = List<String>.from(participantIds);
    createdCategoryId = categoryId;
    createdIsDirectMessage = isDirectMessage;

    return Conversation(
      id: 'new-conv',
      createdAt: DateTime(2024),
      lastActivityAt: DateTime(2024),
      participantIds: participantIds,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test fixtures
// ─────────────────────────────────────────────────────────────────────────────

Member _member({required String id, required String name}) =>
    Member(id: id, name: name, createdAt: DateTime(2024));

Widget _buildSheet({
  required List<Member> members,
  String? speakingAs,
  List<String>? initialMemberIds,
  _FakeChatNotifier? chatNotifier,
}) {
  final notifier = chatNotifier ?? _FakeChatNotifier();
  return ProviderScope(
    overrides: [
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      speakingAsProvider.overrideWith(
        () => _FakeSpeakingAsNotifier(speakingAs),
      ),
      conversationCategoriesProvider.overrideWith((ref) => Stream.value([])),
      chatNotifierProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: CreateConversationSheet(
          scrollController: ScrollController(),
          initialMemberIds: initialMemberIds,
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  final alice = _member(id: 'alice', name: 'Alice');
  final bob = _member(id: 'bob', name: 'Bob');

  // Generate 30 members so the lazy-rendering assertion is meaningful.
  final manyMembers = List.generate(
    30,
    (i) => _member(id: 'member-$i', name: 'Member $i'),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // Lazy member list rendering
  // ══════════════════════════════════════════════════════════════════════════

  group('lazy member list rendering', () {
    testWidgets('does not eagerly build all rows with Column', (tester) async {
      await tester.pumpWidget(_buildSheet(members: manyMembers));
      await tester.pumpAndSettle();

      // With a truly lazy list, fewer than all 30 rows should be built inside
      // the viewport — an eager Column builds them all.
      final built = find.byType(PrismCheckboxRow).evaluate().length;
      expect(
        built,
        lessThan(manyMembers.length),
        reason:
            'Expected lazy list; got $built/${manyMembers.length} rows built',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Search action
  // ══════════════════════════════════════════════════════════════════════════

  group('search action', () {
    testWidgets('search icon button is present in member header', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSheet(members: [alice, bob]));
      await tester.pumpAndSettle();

      expect(find.byIcon(AppIcons.search), findsOneWidget);
    });

    testWidgets('tapping search opens MemberSearchSheet', (tester) async {
      await tester.pumpWidget(_buildSheet(members: [alice, bob]));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Fronting badge in shared search results
  // ══════════════════════════════════════════════════════════════════════════

  group('fronting badge in search results', () {
    testWidgets(
      'fronting badge appears for speaking-as member in MemberSearchSheet',
      (tester) async {
        await tester.pumpWidget(
          _buildSheet(members: [alice, bob], speakingAs: 'alice'),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(AppIcons.search));
        await tester.pumpAndSettle();

        // The "Fronting" badge label should be visible next to Alice.
        expect(
          find.descendant(
            of: find.byType(MemberSearchSheet),
            matching: find.text('Fronting'),
          ),
          findsOneWidget,
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Selected IDs update correctly
  // ══════════════════════════════════════════════════════════════════════════

  group('selected IDs update', () {
    testWidgets('group mode: search selection updates inline selections', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(members: [alice, bob], speakingAs: 'alice'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();

      // Select Bob in the shared search sheet.
      await tester.tap(find.byKey(const ValueKey('bob')));
      await tester.pump();

      // Confirm.
      await tester.tap(find.textContaining('Done'));
      await tester.pumpAndSettle();

      final bobRow = tester.widget<PrismCheckboxRow>(
        find.ancestor(
          of: find.text('Bob').first,
          matching: find.byType(PrismCheckboxRow),
        ),
      );

      expect(find.byType(MemberSearchSheet), findsNothing);
      expect(bobRow.value, isTrue);
    });

    testWidgets(
      'DM mode: search selection is used when creating conversation',
      (tester) async {
        final chatNotifier = _FakeChatNotifier();
        await tester.pumpWidget(
          _buildSheet(
            members: [alice, bob],
            speakingAs: 'alice',
            chatNotifier: chatNotifier,
          ),
        );
        await tester.pumpAndSettle();

        // Switch to DM mode.
        await tester.tap(find.text('Direct Message'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(AppIcons.search));
        await tester.pumpAndSettle();

        // Select Bob.
        await tester.tap(find.byKey(const ValueKey('bob')));
        await tester.pump();

        await tester.tap(find.textContaining('Done'));
        await tester.pumpAndSettle();

        expect(find.byType(MemberSearchSheet), findsNothing);
        await tester.tap(
          find.widgetWithIcon(PrismGlassIconButton, AppIcons.check),
        );
        await tester.pumpAndSettle();

        expect(
          chatNotifier.createdParticipantIds,
          unorderedEquals(['alice', 'bob']),
        );
        expect(chatNotifier.createdIsDirectMessage, isTrue);
      },
    );
  });
}
