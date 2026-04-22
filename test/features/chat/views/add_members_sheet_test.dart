import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/views/add_members_sheet.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_checkbox_row.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fake SpeakingAsNotifier — prevents Drift chain from initializing
// ─────────────────────────────────────────────────────────────────────────────

class _FakeSpeakingAsNotifier extends SpeakingAsNotifier {
  @override
  String? build() => null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Test fixtures
// ─────────────────────────────────────────────────────────────────────────────

Member _member({required String id, required String name}) => Member(
      id: id,
      name: name,
      createdAt: DateTime(2024),
    );

Conversation _conversation({
  String id = 'conv1',
  List<String> participantIds = const [],
}) =>
    Conversation(
      id: id,
      createdAt: DateTime(2024),
      lastActivityAt: DateTime(2024),
      participantIds: participantIds,
    );

// ─────────────────────────────────────────────────────────────────────────────
// Fake ChatNotifier — records addParticipants calls without hitting real repos
// ─────────────────────────────────────────────────────────────────────────────

class _FakeChatNotifier extends ChatNotifier {
  final addedParticipants = <String>[];

  @override
  Future<void> build() async {}

  @override
  Future<void> addParticipants(
    String conversationId,
    List<String> memberIds, {
    String? addedByName,
  }) async {
    addedParticipants.addAll(memberIds);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trigger widget — opens AddMembersSheet on button tap
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildTrigger({
  required Conversation conversation,
  required List<Member> members,
  _FakeChatNotifier? fakeNotifier,
  void Function(bool?)? onResult,
}) {
  return ProviderScope(
    overrides: [
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      speakingAsProvider.overrideWith(() => _FakeSpeakingAsNotifier()),
      if (fakeNotifier != null)
        chatNotifierProvider.overrideWith(() => fakeNotifier),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              final result = await AddMembersSheet.show(ctx, conversation);
              onResult?.call(result);
            },
            child: const Text('Open'),
          ),
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

  // ══════════════════════════════════════════════════════════════════════════
  // Renders through shared multi-select search sheet
  // ══════════════════════════════════════════════════════════════════════════

  group('renders through shared multi-select search sheet', () {
    testWidgets('MemberSearchSheet is present after show is called',
        (tester) async {
      await tester.pumpWidget(
        _buildTrigger(
          conversation: _conversation(),
          members: [alice, bob],
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
    });

    testWidgets('no legacy PrismCheckboxRow picker UI is rendered',
        (tester) async {
      await tester.pumpWidget(
        _buildTrigger(
          conversation: _conversation(),
          members: [alice, bob],
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(PrismCheckboxRow), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Existing participants are excluded
  // ══════════════════════════════════════════════════════════════════════════

  group('existing participants are excluded', () {
    testWidgets('participant is not shown in picker', (tester) async {
      final conv = _conversation(participantIds: ['alice']);
      await tester.pumpWidget(
        _buildTrigger(
          conversation: conv,
          members: [alice, bob],
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
    });

    testWidgets('non-participant members appear in picker', (tester) async {
      final conv = _conversation(participantIds: ['carol']);
      await tester.pumpWidget(
        _buildTrigger(
          conversation: conv,
          members: [alice, bob, carol],
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Confirming triggers add flow
  // ══════════════════════════════════════════════════════════════════════════

  group('confirming triggers add flow', () {
    testWidgets('selecting members and confirming calls addParticipants',
        (tester) async {
      final notifier = _FakeChatNotifier();
      await tester.pumpWidget(
        _buildTrigger(
          conversation: _conversation(id: 'conv1'),
          members: [alice, bob],
          fakeNotifier: notifier,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.text('Bob'));
      await tester.pump();

      await tester.tap(find.textContaining('Done'));
      await tester.pumpAndSettle();

      expect(notifier.addedParticipants, containsAll(['alice', 'bob']));
    });

    testWidgets('show returns true after successful add', (tester) async {
      final notifier = _FakeChatNotifier();
      bool? result;

      await tester.pumpWidget(
        _buildTrigger(
          conversation: _conversation(),
          members: [alice],
          fakeNotifier: notifier,
          onResult: (r) => result = r,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.textContaining('Done'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('dismissing sheet returns null without calling addParticipants',
        (tester) async {
      final notifier = _FakeChatNotifier();
      bool? result = true;

      await tester.pumpWidget(
        _buildTrigger(
          conversation: _conversation(),
          members: [alice],
          fakeNotifier: notifier,
          onResult: (r) => result = r,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.close));
      await tester.pumpAndSettle();

      expect(notifier.addedParticipants, isEmpty);
      expect(result, isNull);
    });
  });
}
