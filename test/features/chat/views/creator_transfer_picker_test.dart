import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/views/creator_transfer_picker.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Member _member({required String id, required String name}) => Member(
      id: id,
      name: name,
      createdAt: DateTime(2024),
    );

/// Builds a trigger widget that calls [showCreatorTransferPicker] on button tap
/// and records the returned [String?] result via [onResult].
Widget _buildTrigger({
  required List<Member> remainingMembers,
  void Function(String?)? onResult,
}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              final result = await showCreatorTransferPicker(
                ctx,
                remainingMembers: remainingMembers,
              );
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
  group('showCreatorTransferPicker', () {
    testWidgets(
        'single remaining member — returns their ID immediately without showing a sheet',
        (tester) async {
      String? result;
      final member = _member(id: 'alice', name: 'Alice');

      await tester.pumpWidget(
        _buildTrigger(
          remainingMembers: [member],
          onResult: (r) => result = r,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Open'));
      // No sheet animation needed — fast path returns synchronously.
      await tester.pump();

      expect(result, 'alice');
      // The search sheet should never have been pushed.
      expect(find.byType(MemberSearchSheet), findsNothing);
    });

    testWidgets('multiple members — shows MemberSearchSheet', (tester) async {
      final members = [
        _member(id: 'alice', name: 'Alice'),
        _member(id: 'bob', name: 'Bob'),
      ];

      await tester.pumpWidget(
        _buildTrigger(remainingMembers: members),
      );
      await tester.pump();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
    });

    testWidgets('selecting a member returns their ID', (tester) async {
      String? result;
      final members = [
        _member(id: 'alice', name: 'Alice'),
        _member(id: 'bob', name: 'Bob'),
      ];

      await tester.pumpWidget(
        _buildTrigger(
          remainingMembers: members,
          onResult: (r) => result = r,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap the member row for Bob.
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();

      expect(result, 'bob');
    });

    testWidgets('dismissing the sheet returns null', (tester) async {
      String? sentinel = 'not-null';
      final members = [
        _member(id: 'alice', name: 'Alice'),
        _member(id: 'bob', name: 'Bob'),
      ];

      await tester.pumpWidget(
        _buildTrigger(
          remainingMembers: members,
          onResult: (r) => sentinel = r,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap the close / cancel icon button in the sheet.
      await tester.tap(find.byType(IconButton).first);
      await tester.pumpAndSettle();

      expect(sentinel, isNull);
    });
  });
}
