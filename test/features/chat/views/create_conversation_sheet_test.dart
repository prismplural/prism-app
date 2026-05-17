import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/conversation_category.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/views/create_conversation_sheet.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/selected_member_picker.dart';

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
  bool? createdIncludesAllMembers;

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
    bool includesAllMembers = false,
  }) async {
    createdTitle = title;
    createdEmoji = emoji;
    createdCreatorId = creatorId;
    createdParticipantIds = List<String>.from(participantIds);
    createdCategoryId = categoryId;
    createdIsDirectMessage = isDirectMessage;
    createdIncludesAllMembers = includesAllMembers;

    return Conversation(
      id: 'new-conv',
      createdAt: DateTime(2024),
      lastActivityAt: DateTime(2024),
      participantIds: participantIds,
      includesAllMembers: includesAllMembers,
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
  Stream<List<Member>>? membersStream,
  String? speakingAs,
  bool useRealSpeakingAsProvider = false,
  List<String>? initialMemberIds,
  bool initialIsGroupChat = true,
  _FakeChatNotifier? chatNotifier,
  List<ConversationCategory> categories = const [],
}) {
  final notifier = chatNotifier ?? _FakeChatNotifier();
  return ProviderScope(
    overrides: [
      activeMembersProvider.overrideWith(
        (ref) => membersStream ?? Stream.value(members),
      ),
      activeSessionsProvider.overrideWithValue(
        const AsyncValue.data(<FrontingSession>[]),
      ),
      allGroupsProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      if (useRealSpeakingAsProvider)
        chatLogsFrontProvider.overrideWithValue(false)
      else
        speakingAsProvider.overrideWith(
          () => _FakeSpeakingAsNotifier(speakingAs),
        ),
      conversationCategoriesProvider.overrideWith(
        (ref) => Stream.value(categories),
      ),
      chatNotifierProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: CreateConversationSheet(
          scrollController: ScrollController(),
          initialMemberIds: initialMemberIds,
          initialIsGroupChat: initialIsGroupChat,
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
  final carol = _member(id: 'carol', name: 'Carol');

  // Generate 30 members so the lazy-rendering assertion is meaningful.
  final manyMembers = List.generate(
    30,
    (i) => _member(id: 'member-$i', name: 'Member $i'),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // Selected member picker
  // ══════════════════════════════════════════════════════════════════════════

  group('selected member picker', () {
    testWidgets('create button has an accessible name', (tester) async {
      await tester.pumpWidget(_buildSheet(members: [alice, bob]));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Create conversation'), findsOneWidget);
      expect(find.bySemanticsLabel('Create conversation'), findsOneWidget);
    });

    testWidgets(
      'uses shared selected-member picker instead of expandable list',
      (tester) async {
        await tester.pumpWidget(_buildSheet(members: manyMembers));
        await tester.pumpAndSettle();

        expect(find.byType(SelectedMultiMemberPicker), findsOneWidget);
        expect(
          find.byKey(const Key('createConversationSelectedMemberPicker')),
          findsOneWidget,
        );
      },
    );

    testWidgets('does not show a Select all participant action', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSheet(members: [alice, bob, carol]));
      await tester.pumpAndSettle();

      expect(find.text('Select All'), findsNothing);
      expect(find.text('Deselect All'), findsNothing);
    });

    testWidgets('starts empty instead of preselecting the current fronter', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(members: [alice, bob], speakingAs: 'alice'),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('selectedMemberPickerSelectButton')),
        findsOneWidget,
      );
      expect(find.text('Alice'), findsNothing);
    });

    testWidgets('can open directly in direct message mode', (tester) async {
      await tester.pumpWidget(
        _buildSheet(
          members: [alice, bob],
          speakingAs: 'alice',
          initialIsGroupChat: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Group Name'), findsNothing);
      expect(find.text('Message as Alice with:'), findsOneWidget);
    });

    testWidgets('select button opens MemberSearchSheet', (tester) async {
      await tester.pumpWidget(_buildSheet(members: [alice, bob]));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('selectedMemberPickerSelectButton')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
    });

    testWidgets('stays layout-safe at transient short sheet heights', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMembersProvider.overrideWith(
              (ref) => Stream.value([alice, bob]),
            ),
            allGroupsProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroup>[]),
            ),
            allGroupEntriesProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroupEntry>[]),
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
            speakingAsProvider.overrideWith(_FakeSpeakingAsNotifier.new),
            conversationCategoriesProvider.overrideWith(
              (ref) => Stream.value([]),
            ),
            chatNotifierProvider.overrideWith(_FakeChatNotifier.new),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: 93,
                    child: CreateConversationSheet(
                      scrollController: ScrollController(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
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

        await tester.tap(
          find.byKey(const Key('selectedMemberPickerSelectButton')),
        );
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
  // Category picker
  // ══════════════════════════════════════════════════════════════════════════

  group('category picker', () {
    testWidgets('opens a dialog for category assignment', (tester) async {
      final category = ConversationCategory(
        id: 'fandoms',
        name: 'Fandoms',
        displayOrder: 0,
        createdAt: DateTime(2026),
        modifiedAt: DateTime(2026),
      );

      await tester.pumpWidget(
        _buildSheet(members: [alice, bob], categories: [category]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Category'));
      await tester.pumpAndSettle();

      expect(find.byType(PrismDialog), findsOneWidget);
      expect(find.text('Fandoms'), findsOneWidget);

      await tester.tap(find.text('Fandoms'));
      await tester.pumpAndSettle();

      expect(find.byType(PrismDialog), findsNothing);
      expect(find.text('Fandoms'), findsOneWidget);
    });
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

      await tester.tap(
        find.byKey(const Key('selectedMemberPickerSelectButton')),
      );
      await tester.pumpAndSettle();

      // Select Bob in the shared search sheet.
      await tester.tap(find.byKey(const ValueKey('bob')));
      await tester.pump();

      // Confirm.
      await tester.tap(
        find.descendant(
          of: find.byType(MemberSearchSheet),
          matching: find.widgetWithIcon(PrismGlassIconButton, AppIcons.check),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsNothing);
      expect(find.text('Bob'), findsWidgets);
      expect(
        find.byKey(const Key('selectedMemberPickerAddButton')),
        findsOneWidget,
      );
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

        await tester.tap(
          find.byKey(const Key('selectedMemberPickerSelectButton')),
        );
        await tester.pumpAndSettle();

        // Select Bob.
        await tester.tap(find.byKey(const ValueKey('bob')));
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

    testWidgets('DM mode: sender can be chosen when no one is fronting', (
      tester,
    ) async {
      final chatNotifier = _FakeChatNotifier();
      await tester.pumpWidget(
        _buildSheet(
          members: [alice, bob],
          useRealSpeakingAsProvider: true,
          chatNotifier: chatNotifier,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Direct Message'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PrismChip, 'Alice'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('selectedMemberPickerSelectButton')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('alice')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('bob')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithIcon(PrismGlassIconButton, AppIcons.check),
      );
      await tester.pumpAndSettle();

      expect(
        chatNotifier.createdParticipantIds,
        unorderedEquals(['alice', 'bob']),
      );
      expect(chatNotifier.createdCreatorId, 'alice');
      expect(chatNotifier.createdIsDirectMessage, isTrue);
    });

    testWidgets(
      'DM mode: changing sender to selected target clears the target',
      (tester) async {
        await tester.pumpWidget(
          _buildSheet(members: [alice, bob], useRealSpeakingAsProvider: true),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Direct Message'));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(PrismChip, 'Alice'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('selectedMemberPickerSelectButton')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('bob')));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(PrismChip, 'Bob'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('selectedMemberPickerSelectButton')),
          findsOneWidget,
        );
        final createButton = tester.widget<PrismGlassIconButton>(
          find.widgetWithIcon(PrismGlassIconButton, AppIcons.check),
        );
        expect(createButton.onPressed, isNull);

        await tester.tap(
          find.byKey(const Key('selectedMemberPickerSelectButton')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('bob')), findsNothing);
        expect(find.byKey(const ValueKey('alice')), findsOneWidget);
      },
    );

    testWidgets('DM mode: inactive selected target is pruned', (tester) async {
      final membersController = StreamController<List<Member>>();
      addTearDown(membersController.close);

      await tester.pumpWidget(
        _buildSheet(
          members: const [],
          membersStream: membersController.stream,
          useRealSpeakingAsProvider: true,
        ),
      );

      membersController.add([alice, bob, carol]);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Direct Message'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PrismChip, 'Alice'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('selectedMemberPickerSelectButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bob')));
      await tester.pumpAndSettle();

      membersController.add([alice, carol]);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('selectedMemberPickerSelectButton')),
        findsOneWidget,
      );
      final createButton = tester.widget<PrismGlassIconButton>(
        find.widgetWithIcon(PrismGlassIconButton, AppIcons.check),
      );
      expect(createButton.onPressed, isNull);

      await tester.tap(
        find.byKey(const Key('selectedMemberPickerSelectButton')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('bob')), findsNothing);
      expect(find.byKey(const ValueKey('carol')), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Include-everyone toggle
  // ══════════════════════════════════════════════════════════════════════════

  group('include-everyone toggle', () {
    testWidgets('shows the toggle in group mode and hides it in DM mode', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSheet(members: [alice, bob]));
      await tester.pumpAndSettle();

      expect(find.text('Include everyone'), findsOneWidget);

      // Switch to DM tab.
      await tester.tap(find.text('Direct Message'));
      await tester.pumpAndSettle();
      expect(find.text('Include everyone'), findsNothing);
    });

    testWidgets('flipping it on hides the member picker', (tester) async {
      await tester.pumpWidget(_buildSheet(members: [alice, bob]));
      await tester.pumpAndSettle();

      // Picker is present by default.
      expect(find.byType(SelectedMultiMemberPicker), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.byType(SelectedMultiMemberPicker), findsNothing);
      expect(find.text('Select participants (2+)'), findsNothing);
    });

    testWidgets(
      'creates the conversation with includesAllMembers=true and creator-only participants',
      (tester) async {
        final notifier = _FakeChatNotifier();
        await tester.pumpWidget(
          _buildSheet(
            members: [alice, bob, carol],
            speakingAs: 'alice',
            chatNotifier: notifier,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'Everyone Chat');
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        // Even with zero explicit member picks, create should be enabled
        // (everyone-groups don't require the 2+ member selection).
        await tester.tap(find.byTooltip('Create conversation'));
        await tester.pumpAndSettle();

        expect(notifier.createdIncludesAllMembers, isTrue);
        expect(notifier.createdTitle, 'Everyone Chat');
        expect(
          notifier.createdParticipantIds,
          ['alice'],
          reason:
              'Everyone-groups store the creator only; other members are '
              'implicit via the flag.',
        );
        expect(notifier.createdIsDirectMessage, isFalse);
      },
    );

    testWidgets(
      'with toggle off, defaults to includesAllMembers=false and requires 2+ picks',
      (tester) async {
        final notifier = _FakeChatNotifier();
        await tester.pumpWidget(
          _buildSheet(
            members: [alice, bob, carol],
            speakingAs: 'alice',
            initialMemberIds: ['alice', 'bob'],
            chatNotifier: notifier,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'Normal Group');
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Create conversation'));
        await tester.pumpAndSettle();

        expect(notifier.createdIncludesAllMembers, isFalse);
        expect(notifier.createdParticipantIds, ['alice', 'bob']);
      },
    );

    testWidgets(
      'Unknown sentinel speakingAs is treated as no creator for everyone-groups',
      (tester) async {
        // Selecting "Unknown" as the speaker is valid for messaging but
        // cannot be a conversation owner — same orphan-ownership risk as
        // null speakingAs.
        final notifier = _FakeChatNotifier();
        await tester.pumpWidget(
          _buildSheet(
            members: [alice, bob],
            speakingAs: unknownSentinelMemberId,
            chatNotifier: notifier,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'Everyone Chat');
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Create conversation'));
        await tester.pumpAndSettle();

        expect(
          notifier.createdIncludesAllMembers,
          isNull,
          reason: 'create button must be disabled for Unknown speakingAs',
        );
      },
    );

    testWidgets('DM creation is blocked when speakingAs is Unknown', (
      tester,
    ) async {
      // Unknown landing in DM participantIds would let anyone else
      // selecting Unknown match as a real participant and read the DM.
      final notifier = _FakeChatNotifier();
      await tester.pumpWidget(
        _buildSheet(
          members: [alice, bob],
          speakingAs: unknownSentinelMemberId,
          initialIsGroupChat: false,
          initialMemberIds: ['bob'],
          chatNotifier: notifier,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Create conversation'));
      await tester.pumpAndSettle();

      expect(
        notifier.createdIsDirectMessage,
        isNull,
        reason: 'create button must be disabled for Unknown DM',
      );
    });

    testWidgets(
      'normal group with Unknown speakingAs falls back to first picked member as creator',
      (tester) async {
        // Unknown is allowed as speaker for the message stream, but the
        // notifier shouldn't be handed the sentinel as creatorId.
        final notifier = _FakeChatNotifier();
        await tester.pumpWidget(
          _buildSheet(
            members: [alice, bob, carol],
            speakingAs: unknownSentinelMemberId,
            initialMemberIds: ['alice', 'bob'],
            chatNotifier: notifier,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'Group');
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Create conversation'));
        await tester.pumpAndSettle();

        expect(
          notifier.createdCreatorId,
          'alice',
          reason: 'creator should fall back to first picked real member',
        );
        expect(notifier.createdParticipantIds, ['alice', 'bob']);
      },
    );

    testWidgets(
      'with no speakingAs picked, create is disabled to avoid orphan ownership',
      (tester) async {
        // Without a fronter, an everyone-group create would persist an empty
        // creatorId — leaving the chat unmanageable by anyone except admins.
        final notifier = _FakeChatNotifier();
        await tester.pumpWidget(
          _buildSheet(
            members: [alice, bob],
            speakingAs: null,
            chatNotifier: notifier,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'Everyone Chat');
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Create conversation'));
        await tester.pumpAndSettle();

        expect(
          notifier.createdIncludesAllMembers,
          isNull,
          reason: 'create button should be disabled, notifier never called',
        );
        expect(notifier.createdTitle, isNull);
      },
    );
  });
}
