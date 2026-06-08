import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/features/notes/widgets/notes_filter_bar.dart';
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

    Widget buildSubject({
      String searchQuery = '',
      bool autofocus = false,
      String? filterMemberId,
      String? filterMemberName,
      Widget? filterMemberAvatar,
      VoidCallback? onClearSearch,
      ValueChanged<String>? onSearchChanged,
      VoidCallback? onClearAllFilters,
      VoidCallback? onClearMemberFilter,
    }) {
      return ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: NotesFilterBar(
              searchController: searchController,
              searchQuery: searchQuery,
              autofocus: autofocus,
              onSearchChanged: onSearchChanged ?? (_) {},
              onClearSearch: onClearSearch ?? () {},
              onClearAllFilters: onClearAllFilters ?? () {},
              filterMemberId: filterMemberId,
              filterMemberName: filterMemberName,
              filterMemberAvatar: filterMemberAvatar,
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

    testWidgets('does not show clear button when searchQuery is empty',
        (tester) async {
      await tester.pumpWidget(buildSubject(searchQuery: ''));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Clear filters'), findsNothing);
    });

    testWidgets('shows clear button when searchQuery is not empty',
        (tester) async {
      await tester.pumpWidget(buildSubject(searchQuery: 'test'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Clear filters'), findsOneWidget);
    });

    testWidgets('calls onClearSearch when clear button tapped',
        (tester) async {
      var cleared = false;
      await tester.pumpWidget(
        buildSubject(
          searchQuery: 'test',
          onClearSearch: () => cleared = true,
        ),
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

    testWidgets('shows member chip when filterMemberId is set',
        (tester) async {
      await tester.pumpWidget(
        buildSubject(filterMemberId: 'mem-a', filterMemberName: 'Alice'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PrismChip), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows No member label when filterMemberName is null',
        (tester) async {
      await tester.pumpWidget(
        buildSubject(filterMemberId: '__filter_no_member__'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PrismChip), findsOneWidget);
      expect(find.text('No member'), findsOneWidget);
    });

    testWidgets('does not show member chip when filterMemberId is null',
        (tester) async {
      await tester.pumpWidget(buildSubject(filterMemberId: null));
      await tester.pumpAndSettle();

      expect(find.byType(PrismChip), findsNothing);
    });

    testWidgets('calls onClearMemberFilter when chip tapped', (tester) async {
      var cleared = false;
      await tester.pumpWidget(
        buildSubject(
          filterMemberId: 'mem-a',
          filterMemberName: 'Alice',
          onClearMemberFilter: () => cleared = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PrismChip));
      expect(cleared, isTrue);
    });

    testWidgets('calls onClearAllFilters when trailing X tapped',
        (tester) async {
      var clearedAll = false;
      await tester.pumpWidget(
        buildSubject(
          filterMemberId: 'mem-a',
          filterMemberName: 'Alice',
          onClearAllFilters: () => clearedAll = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clearAllFilters')));
      expect(clearedAll, isTrue);
    });
  });
}
