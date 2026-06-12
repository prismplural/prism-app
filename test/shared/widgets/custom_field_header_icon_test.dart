import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/shared/icons/phosphor_icon_catalog.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/custom_field_header_icon.dart';

void main() {
  CustomField field({
    required String id,
    required CustomFieldType type,
    String? fieldTypeId,
    CustomFieldTypeConfig? typeConfig,
  }) {
    return CustomField(
      id: id,
      name: id,
      fieldType: type,
      fieldTypeId: fieldTypeId,
      typeConfig: typeConfig,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  testWidgets('renders a persisted phosphor header icon by name', (
    tester,
  ) async {
    final heart = PhosphorIconCatalog.iconFor('heart')!;

    await tester.pumpWidget(
      MaterialApp(
        home: CustomFieldHeaderIconView(
          field: field(
            id: 'song',
            type: CustomFieldType.text,
            fieldTypeId: 'text',
            typeConfig: const TextConfig(
              headerIcon: CustomFieldHeaderIcon.phosphor('heart'),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(heart), findsOneWidget);
  });

  testWidgets('renders emoji header icons without avatar centering transform', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomFieldHeaderIconView(
            size: 16,
            field: field(
              id: 'direction',
              type: CustomFieldType.text,
              fieldTypeId: 'text',
              typeConfig: const TextConfig(
                headerIcon: CustomFieldHeaderIcon.emoji('🧭'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('🧭'), findsOneWidget);
      final iconRect = tester.getRect(find.byType(CustomFieldHeaderIconView));
      final emojiRect = tester.getRect(find.text('🧭'));
      expect(emojiRect.top, greaterThanOrEqualTo(iconRect.top));
      expect(emojiRect.bottom, lessThanOrEqualTo(iconRect.bottom));
      expect(
        find.descendant(
          of: find.byType(CustomFieldHeaderIconView),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('falls back to the registry or legacy field type icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomFieldHeaderIconView(
          field: field(id: 'birthday', type: CustomFieldType.date),
        ),
      ),
    );

    expect(find.byIcon(AppIcons.calendarToday), findsOneWidget);
  });
}
