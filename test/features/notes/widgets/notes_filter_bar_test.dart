import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/features/notes/widgets/notes_filter_bar.dart';
import 'package:prism_plurality/shared/widgets/member_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

void main() {
  group('NotesFilterBar', () {
    late TextEditingController searchController;

    setUp(() {
      searchController = TextEditingController();
    });

    tearDown(() {
      searchController.dispose();
    });

    Member member({
      String id = 'mem-a',
      String name = 'Alice',
      bool customColorEnabled = false,
      String? customColorHex,
    }) {
      return Member(
        id: id,
        name: name,
        customColorEnabled: customColorEnabled,
        customColorHex: customColorHex,
        createdAt: DateTime(2026, 1, 1),
      );
    }

    Widget buildSubject({
      bool showSearch = true,
      String searchQuery = '',
      bool autofocus = false,
      List<NotesMemberFilter> memberFilters = const [],
      VoidCallback? onClearSearch,
      ValueChanged<String>? onSearchChanged,
      VoidCallback? onClearAllFilters,
      ValueChanged<String>? onClearMemberFilter,
    }) {
      return ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: NotesFilterBar(
                showSearch: showSearch,
                searchController: searchController,
                searchQuery: searchQuery,
                autofocus: autofocus,
                onSearchChanged: onSearchChanged ?? (_) {},
                onClearSearch: onClearSearch ?? () {},
                onClearAllFilters: onClearAllFilters ?? () {},
                memberFilters: memberFilters,
                onClearMemberFilter: onClearMemberFilter,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('renders search field with search icon', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.byType(PrismTextField), findsOneWidget);
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('does not show clear button when searchQuery is empty', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject(searchQuery: ''));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Clear filters'), findsNothing);
    });

    testWidgets('shows clear button when searchQuery is not empty', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject(searchQuery: 'test'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Clear filters'), findsOneWidget);
    });

    testWidgets('calls onClearSearch when clear button tapped', (tester) async {
      var cleared = false;
      await tester.pumpWidget(
        buildSubject(searchQuery: 'test', onClearSearch: () => cleared = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Clear filters'));
      expect(cleared, isTrue);
    });

    testWidgets('calls onSearchChanged when text changes', (tester) async {
      String? changedValue;
      await tester.pumpWidget(
        buildSubject(onSearchChanged: (v) => changedValue = v),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(PrismTextField), 'hello');
      expect(changedValue, 'hello');
    });

    testWidgets('shows member chip when member filter is set', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          memberFilters: [
            NotesMemberFilter(id: 'mem-a', label: 'Alice', member: member()),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MemberChip), findsOneWidget);
      expect(find.byType(PrismChip), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows active member filter without opening search field', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          showSearch: false,
          memberFilters: [
            NotesMemberFilter(id: 'mem-a', label: 'Alice', member: member()),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MemberChip), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.byType(PrismTextField), findsNothing);
    });

    testWidgets('shows No member label', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          memberFilters: const [
            NotesMemberFilter(id: '__filter_no_member__', label: 'No member'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PrismChip), findsOneWidget);
      expect(find.text('No member'), findsOneWidget);
    });

    testWidgets('does not show member chip when member filters are empty', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.byType(PrismChip), findsNothing);
    });

    testWidgets('shows multiple member chips', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          memberFilters: [
            NotesMemberFilter(id: 'mem-a', label: 'Alice', member: member()),
            NotesMemberFilter(
              id: 'mem-b',
              label: 'Bob',
              member: member(id: 'mem-b', name: 'Bob'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MemberChip), findsNWidgets(2));
      expect(find.byType(PrismChip), findsNWidgets(2));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('uses member chip accent color calculation', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          memberFilters: [
            NotesMemberFilter(
              id: 'mem-a',
              label: 'Alice',
              member: member(
                customColorEnabled: true,
                customColorHex: '#00AAFF',
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final chip = tester.widget<PrismChip>(find.byType(PrismChip));
      expect(chip.selectedColor, const Color(0xFF00AAFF));
      expect(chip.variant, PrismChipVariant.filled);
    });

    testWidgets('calls onClearMemberFilter when chip tapped', (tester) async {
      String? clearedMemberId;
      await tester.pumpWidget(
        buildSubject(
          memberFilters: const [NotesMemberFilter(id: 'mem-a', label: 'Alice')],
          onClearMemberFilter: (memberId) => clearedMemberId = memberId,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PrismChip));
      expect(clearedMemberId, 'mem-a');
    });

    testWidgets('calls onClearAllFilters when trailing X tapped', (
      tester,
    ) async {
      var clearedAll = false;
      await tester.pumpWidget(
        buildSubject(
          memberFilters: const [NotesMemberFilter(id: 'mem-a', label: 'Alice')],
          onClearAllFilters: () => clearedAll = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clearAllFilters')));
      expect(clearedAll, isTrue);
    });
  });
}
