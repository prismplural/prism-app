import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/conversation_category.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/chat/widgets/category_management_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

void main() {
  testWidgets(
    'category manager scroll content clears system navigation inset',
    (tester) async {
      final categories = [
        ConversationCategory(
          id: 'cat-1',
          name: 'Important',
          displayOrder: 0,
          createdAt: DateTime(2026),
          modifiedAt: DateTime(2026),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationCategoriesProvider.overrideWith(
              (ref) => Stream.value(categories),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 720),
                viewPadding: EdgeInsets.only(bottom: 48),
              ),
              child: const Scaffold(body: CategoryManagementSheet()),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(
        listView.padding,
        const EdgeInsets.fromLTRB(
          PrismTokens.pageHorizontalPadding,
          0,
          PrismTokens.pageHorizontalPadding,
          56,
        ),
      );
    },
  );
}
