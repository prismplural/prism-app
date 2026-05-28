import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_fields_display.dart';
import 'package:prism_plurality/features/members/widgets/slider_field_widgets.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

void main() {
  const memberId = 'member-1';

  Widget subject({
    required List<CustomField> fields,
    required List<CustomFieldValue> values,
  }) {
    return ProviderScope(
      overrides: [
        customFieldsProvider.overrideWithValue(AsyncValue.data(fields)),
        memberCustomFieldValuesProvider(
          memberId,
        ).overrideWithValue(AsyncValue.data(values)),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomFieldsDisplay(memberId: memberId),
          ),
        ),
      ),
    );
  }

  CustomField field(String id, CustomFieldType type, {String? name}) =>
      CustomField(
        id: id,
        name: name ?? 'Field $id',
        fieldType: type,
        fieldTypeId: _fieldTypeIdFor(type),
        createdAt: DateTime(2026, 1, 1),
      );

  CustomFieldValue value(String fieldId, String text) => CustomFieldValue(
    id: 'value-$fieldId',
    customFieldId: fieldId,
    memberId: memberId,
    value: text,
  );

  testWidgets('short text fields render inline markdown', (tester) async {
    await tester.pumpWidget(
      subject(
        fields: [field('short', CustomFieldType.text)],
        values: [value('short', 'hello **bold** and __strong__')],
      ),
    );
    await tester.pump();

    final span = _findTextSpanWithPlainText(tester, 'hello bold and strong');
    expect(span, isNotNull);
    expect(_spanForText(span!, 'bold')?.style?.fontWeight, FontWeight.bold);
    expect(_spanForText(span, 'strong')?.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('long text fields use full markdown rendering', (tester) async {
    await tester.pumpWidget(
      subject(
        fields: [field('long', CustomFieldType.longText)],
        values: [value('long', '# Heading\n\nBody text')],
      ),
    );
    await tester.pump();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text('Field long'), findsOneWidget);
  });

  testWidgets(
    'read-only slider fields do not instantiate Material Slider controls',
    (tester) async {
      final fields = List.generate(
        24,
        (i) => CustomField(
          id: 'slider-$i',
          name: 'Slider $i',
          fieldType: CustomFieldType.text,
          fieldTypeId: 'slider',
          displayOrder: i,
          createdAt: DateTime(2026, 1, 1),
          typeConfig: const SliderConfig(
            mode: SliderMode.labeled,
            leftLabel: 'Low',
            rightLabel: 'High',
            gradientPresetId: 'sad-happy',
          ),
        ),
      );

      await tester.pumpWidget(
        subject(
          fields: fields,
          values: [
            for (var i = 0; i < fields.length; i++)
              value(fields[i].id, '${(i * 4) % 101}'),
          ],
        ),
      );
      await tester.pump();

      expect(
        find.byType(Slider),
        findsNothing,
        reason:
            'Profile display is read-only; many full Slider controls '
            'make slider-heavy profiles expensive to scroll.',
      );
    },
  );

  testWidgets('read-only slider semantics does not duplicate visible label', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();

    final sliderField = CustomField(
      id: 'slider-mood',
      name: 'Mood',
      fieldType: CustomFieldType.text,
      fieldTypeId: 'slider',
      createdAt: DateTime(2026, 1, 1),
      typeConfig: const SliderConfig(
        mode: SliderMode.labeled,
        leftLabel: 'Low',
        rightLabel: 'High',
        gradientPresetId: 'sad-happy',
      ),
    );

    await tester.pumpWidget(
      subject(fields: [sliderField], values: [value(sliderField.id, '64')]),
    );
    await tester.pump();

    expect(find.text('Mood'), findsOneWidget);
    expect(find.bySemanticsLabel('Mood'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == null &&
            widget.properties.value == 'High, 64%',
      ),
      findsOneWidget,
    );

    semanticsHandle.dispose();
  });

  testWidgets(
    'static slider renderer preserves track/thumb geometry and tick variants',
    (tester) async {
      const labeledConfig = SliderConfig(
        mode: SliderMode.labeled,
        leftLabel: 'Low',
        rightLabel: 'High',
        gradientPresetId: 'sad-happy',
      );
      await _expectStaticSliderPaintGeometry(
        tester,
        config: labeledConfig,
        value: 64,
        indicatorLabel: 'High, 64%',
        expectedTrackRRect: RRect.fromLTRBR(
          0,
          20,
          320,
          28,
          const Radius.circular(4),
        ),
        expectedThumbRRect: RRect.fromLTRBR(
          193.8,
          13,
          215.8,
          35,
          const Radius.circular(11),
        ),
        expectedTickCenters: const [],
        expectedTickRadius: 0,
      );

      const numericConfig = SliderConfig(
        mode: SliderMode.numeric,
        min: 0,
        max: 10,
        step: 1,
        unit: 'x',
      );
      await _expectStaticSliderPaintGeometry(
        tester,
        config: numericConfig,
        value: 6,
        indicatorLabel: '6x',
        expectedTrackRRect: RRect.fromLTRBR(
          0,
          21,
          194,
          27,
          const Radius.circular(3),
        ),
        expectedThumbRRect: RRect.fromLTRBR(
          170.5,
          13,
          213.5,
          35,
          const Radius.circular(11),
        ),
        expectedTickCenters: const [],
        expectedTickRadius: 0,
      );

      const labeledSnapConfig = SliderConfig(
        mode: SliderMode.labeled,
        leftLabel: 'Low',
        rightLabel: 'High',
        gradientPresetId: 'sad-happy',
        snapToPositions: true,
      );
      await _expectStaticSliderPaintGeometry(
        tester,
        config: labeledSnapConfig,
        value: 50,
        indicatorLabel: 'High, 50%',
        expectedTrackRRect: RRect.fromLTRBR(
          0,
          20,
          320,
          28,
          const Radius.circular(4),
        ),
        expectedThumbRRect: RRect.fromLTRBR(
          149,
          13,
          171,
          35,
          const Radius.circular(11),
        ),
        expectedTickCenters: const [
          Offset(4, 24),
          Offset(160, 24),
          Offset(316, 24),
        ],
        expectedTickRadius: 2,
      );

      const labeledCenterSnapConfig = SliderConfig(
        mode: SliderMode.labeled,
        leftLabel: 'Low',
        centerLabel: 'Mid',
        rightLabel: 'High',
        gradientPresetId: 'sad-happy',
        snapToPositions: true,
      );
      await _expectStaticSliderPaintGeometry(
        tester,
        config: labeledCenterSnapConfig,
        value: 75,
        indicatorLabel: 'High, 75%',
        expectedTrackRRect: RRect.fromLTRBR(
          0,
          20,
          320,
          28,
          const Radius.circular(4),
        ),
        expectedThumbRRect: RRect.fromLTRBR(
          229,
          13,
          251,
          35,
          const Radius.circular(11),
        ),
        expectedTickCenters: const [
          Offset(4, 24),
          Offset(82, 24),
          Offset(160, 24),
          Offset(238, 24),
          Offset(316, 24),
        ],
        expectedTickRadius: 2,
      );

      const numericTicksConfig = SliderConfig(
        mode: SliderMode.numeric,
        min: 0,
        max: 10,
        step: 2,
        unit: 'x',
        showTicks: true,
      );
      await _expectStaticSliderPaintGeometry(
        tester,
        config: numericTicksConfig,
        value: 6,
        indicatorLabel: '6x',
        expectedTrackRRect: RRect.fromLTRBR(
          0,
          21,
          194,
          27,
          const Radius.circular(3),
        ),
        expectedThumbRRect: RRect.fromLTRBR(
          170.5,
          13,
          213.5,
          35,
          const Radius.circular(11),
        ),
        expectedTickCenters: const [
          Offset(2, 24),
          Offset(65.2, 24),
          Offset(128.4, 24),
          Offset(191.6, 24),
          Offset(254.8, 24),
          Offset(318, 24),
        ],
        expectedTickRadius: 1,
      );

      const denseNumericTicksConfig = SliderConfig(
        mode: SliderMode.numeric,
        min: 0,
        max: 100,
        step: 1,
        showTicks: true,
      );
      await _expectStaticSliderPaintGeometry(
        tester,
        config: denseNumericTicksConfig,
        value: 41,
        indicatorLabel: '41',
        expectedTrackRRect: RRect.fromLTRBR(
          0,
          21,
          133.2,
          27,
          const Radius.circular(3),
        ),
        expectedThumbRRect: RRect.fromLTRBR(
          109.7,
          13,
          152.7,
          35,
          const Radius.circular(11),
        ),
        expectedTickCenters: const [Offset(2, 24), Offset(318, 24)],
        expectedTickRadius: 1,
        expectedTickCount: 51,
      );
    },
  );

  testWidgets('slider label variants render expected profile label rows', (
    tester,
  ) async {
    final noCenter = CustomField(
      id: 'slider-no-center',
      name: 'No center',
      fieldType: CustomFieldType.text,
      fieldTypeId: 'slider',
      displayOrder: 0,
      createdAt: DateTime(2026, 1, 1),
      typeConfig: const SliderConfig(
        mode: SliderMode.labeled,
        leftLabel: 'Low anchor only',
        rightLabel: 'High anchor only',
        gradientPresetId: 'sad-happy',
      ),
    );
    final withCenter = CustomField(
      id: 'slider-with-center',
      name: 'With center',
      fieldType: CustomFieldType.text,
      fieldTypeId: 'slider',
      displayOrder: 1,
      createdAt: DateTime(2026, 1, 1),
      typeConfig: const SliderConfig(
        mode: SliderMode.labeled,
        leftLabel: 'Left edge label',
        centerLabel: 'Middle label',
        rightLabel: 'Right edge label',
        gradientPresetId: 'sad-happy',
      ),
    );
    final noLabels = CustomField(
      id: 'slider-no-labels',
      name: 'No labels',
      fieldType: CustomFieldType.text,
      fieldTypeId: 'slider',
      displayOrder: 2,
      createdAt: DateTime(2026, 1, 1),
      typeConfig: const SliderConfig(
        mode: SliderMode.labeled,
        gradientPresetId: 'sad-happy',
      ),
    );

    await tester.pumpWidget(
      subject(
        fields: [noCenter, withCenter, noLabels],
        values: [
          value(noCenter.id, '25'),
          value(withCenter.id, '50'),
          value(noLabels.id, '75'),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Low anchor only'), findsOneWidget);
    expect(find.text('High anchor only'), findsOneWidget);
    expect(find.text('Middle label'), findsOneWidget);
    expect(find.text('Left edge label'), findsOneWidget);
    expect(find.text('Right edge label'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });

  testWidgets('short text stays grouped even with long names and values', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        fields: [
          field('short', CustomFieldType.text, name: 'Role'),
          field(
            'medium',
            CustomFieldType.text,
            name: 'Detailed internal relationship context',
          ),
        ],
        values: [
          value('short', 'Protector'),
          value(
            'medium',
            'Often prefers quiet check-ins after stressful days.',
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(PrismSectionCard), findsOneWidget);
    expect(find.byType(PrismSurface), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Detailed internal relationship context'), findsOneWidget);
  });

  testWidgets('profile custom fields omit the section header', (tester) async {
    await tester.pumpWidget(
      subject(
        fields: [field('short', CustomFieldType.text)],
        values: [value('short', 'Protector')],
      ),
    );
    await tester.pump();

    expect(find.text('Custom Fields'), findsNothing);
    expect(find.text('Field short'), findsOneWidget);
    expect(find.text('Protector'), findsOneWidget);
  });

  testWidgets('long text truncates and opens full detail sheet', (
    tester,
  ) async {
    final longBody = '${List.filled(180, 'filler').join(' ')} FINAL_SENTINEL';

    await tester.pumpWidget(
      subject(
        fields: [field('bio', CustomFieldType.longText, name: 'Second bio')],
        values: [value('bio', longBody)],
      ),
    );
    await tester.pump();

    expect(find.text('View more'), findsOneWidget);
    expect(_hasRichTextContaining(tester, 'FINAL_SENTINEL'), isFalse);

    await tester.ensureVisible(find.text('View more'));
    await tester.tap(find.text('View more'));
    await tester.pumpAndSettle();

    expect(find.text('Second bio'), findsWidgets);
    expect(_hasRichTextContaining(tester, 'FINAL_SENTINEL'), isTrue);
  });

  // ── hideTitleOnProfile tests ────────────────────────────────────────────────

  testWidgets(
    'hidden-title text field with a value: name and icon hidden, value + semantics only',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      const fieldName = 'Secret Role';
      final hiddenField = CustomField(
        id: 'ht1',
        name: fieldName,
        fieldType: CustomFieldType.text,
        createdAt: DateTime(2026, 1, 1),
        typeConfig: const TextConfig(hideTitleOnProfile: true),
      );

      await tester.pumpWidget(
        subject(fields: [hiddenField], values: [value('ht1', 'Protector')]),
      );
      await tester.pump();

      // The field name must NOT be visible as a Text widget.
      expect(find.text(fieldName), findsNothing);

      // The value IS rendered.
      expect(_hasRichTextContaining(tester, 'Protector'), isTrue);

      // No type-icon affordance — a hidden-title field renders value-only.
      expect(find.byType(Icon), findsNothing);

      // The semantics tree must include a node labelled with the field name
      // so screen readers can announce it. The merged label includes both the
      // Semantics.label and the child text ("Secret Role\nProtector"), so
      // match by regex prefix.
      expect(
        find.bySemanticsLabel(RegExp(fieldName)),
        findsWidgets,
        reason: 'Semantics wrapper must carry the field name as its label',
      );

      semanticsHandle.dispose();
    },
  );

  testWidgets('hidden-title field card stretches to the full available width', (
    tester,
  ) async {
    // One short "Other" chip is far narrower than the viewport, so a card
    // without a full-width constraint shrink-wraps to it. Regression guard.
    final choiceField = CustomField(
      id: 'cw1',
      name: 'Options',
      fieldType:
          CustomFieldType.text, // legacy enum; fieldTypeId drives routing
      fieldTypeId: 'choice',
      createdAt: DateTime(2026, 1, 1),
      typeConfig: const ChoiceConfig(hideTitleOnProfile: true),
    );

    await tester.pumpWidget(
      subject(fields: [choiceField], values: [value('cw1', '{"other":"hi"}')]),
    );
    await tester.pump();

    // Measure against the Scaffold: the scroll view shrink-wraps to its
    // content, so it would collapse with the card and mask the bug.
    final cardWidth = tester.getSize(find.byType(PrismSurface)).width;
    final scaffoldWidth = tester.getSize(find.byType(Scaffold)).width;
    expect(cardWidth, scaffoldWidth);
  });

  testWidgets('hidden-title text field with empty value renders nothing', (
    tester,
  ) async {
    final hiddenField = CustomField(
      id: 'ht2',
      name: 'Hidden Empty',
      fieldType: CustomFieldType.text,
      createdAt: DateTime(2026, 1, 1),
      typeConfig: const TextConfig(hideTitleOnProfile: true),
    );

    // No value provided for this field — the display should emit nothing.
    await tester.pumpWidget(subject(fields: [hiddenField], values: []));
    await tester.pump();

    expect(find.byType(PrismSurface), findsNothing);
    expect(find.byType(PrismSectionCard), findsNothing);
  });

  testWidgets(
    'mixed run: two normal compact fields group together, hidden-title field renders separately',
    (tester) async {
      const normalName1 = 'Role';
      const normalName2 = 'Mood';
      const hiddenName = 'Inner Note';

      final normalField1 = CustomField(
        id: 'n1',
        name: normalName1,
        fieldType: CustomFieldType.text,
        createdAt: DateTime(2026, 1, 1),
      );
      final normalField2 = CustomField(
        id: 'n2',
        name: normalName2,
        fieldType: CustomFieldType.text,
        createdAt: DateTime(2026, 1, 1),
      );
      final hiddenField = CustomField(
        id: 'ht3',
        name: hiddenName,
        fieldType: CustomFieldType.text,
        createdAt: DateTime(2026, 1, 1),
        typeConfig: const TextConfig(hideTitleOnProfile: true),
      );

      await tester.pumpWidget(
        subject(
          // Order: normal, normal, hidden — so first two form a compact run.
          fields: [normalField1, normalField2, hiddenField],
          values: [
            value('n1', 'Protector'),
            value('n2', 'Calm'),
            value('ht3', 'Quiet observer'),
          ],
        ),
      );
      await tester.pump();

      // The two normal names are visible.
      expect(find.text(normalName1), findsOneWidget);
      expect(find.text(normalName2), findsOneWidget);

      // The hidden field's name is NOT visible.
      expect(find.text(hiddenName), findsNothing);

      // There are two surfaces: one PrismSectionCard (compact group for the two
      // normal fields) + one PrismSurface (hidden-title card). The hidden-title
      // card is a separate PrismSurface, not inside the compact group.
      expect(find.byType(PrismSectionCard), findsOneWidget);
      expect(find.byType(PrismSurface), findsAtLeast(1));
    },
  );

  testWidgets(
    'hidden-title scale field (stacked layout): no bold title text, body still renders',
    (tester) async {
      // Scale is chosen because it is the only non-slider type that can be
      // forced into DisplayLayout.stacked via its ScaleConfig.displayLayout
      // field. This lets us test the _FieldValueStacked hideTitle path without
      // needing to supply a slider-specific value format.
      final semanticsHandle = tester.ensureSemantics();
      const fieldName = 'Mood Scale';
      final scaleField = CustomField(
        id: 'sc1',
        name: fieldName,
        fieldType:
            CustomFieldType.text, // legacy enum; fieldTypeId drives routing
        fieldTypeId: 'scale',
        createdAt: DateTime(2026, 1, 1),
        typeConfig: const ScaleConfig(
          hideTitleOnProfile: true,
          displayLayout: DisplayLayout.stacked,
        ),
      );

      // Scale values are stored as "N/max" integers; "3" is a valid raw value.
      await tester.pumpWidget(
        subject(fields: [scaleField], values: [value('sc1', '3')]),
      );
      await tester.pump();

      // The bold title Text with the field name must not appear.
      expect(find.text(fieldName), findsNothing);

      // The card itself is rendered (some widget in the tree).
      expect(find.byType(PrismSectionCard), findsOneWidget);

      // Semantics label carries the field name for accessibility.
      // The merged label may include both the Semantics.label and child content
      // so match by regex rather than exact string.
      expect(find.bySemanticsLabel(RegExp(fieldName)), findsWidgets);

      semanticsHandle.dispose();
    },
  );

  testWidgets(
    'group child with hideTitleOnProfile hides its own label, sibling keeps it',
    (tester) async {
      // Per-child opt-out inside a group, independent of the group's own
      // toggle. Regression: child title was always shown.
      final group = CustomField(
        id: 'grp',
        name: 'My Group',
        fieldType: CustomFieldType.text,
        fieldTypeId: 'group',
        createdAt: DateTime(2026, 1, 1),
        typeConfig: const GroupConfig(),
      );
      final hiddenChild = CustomField(
        id: 'child-hidden',
        name: 'Secret Child',
        fieldType: CustomFieldType.text,
        fieldTypeId: 'text',
        parentFieldId: 'grp',
        displayOrder: 0,
        createdAt: DateTime(2026, 1, 1),
        typeConfig: const TextConfig(hideTitleOnProfile: true),
      );
      final shownChild = CustomField(
        id: 'child-shown',
        name: 'Shown Child',
        fieldType: CustomFieldType.text,
        fieldTypeId: 'text',
        parentFieldId: 'grp',
        displayOrder: 1,
        createdAt: DateTime(2026, 1, 1),
      );

      final semanticsHandle = tester.ensureSemantics();
      await tester.pumpWidget(
        subject(
          fields: [group, hiddenChild, shownChild],
          values: [
            value('child-hidden', 'hidden-val'),
            value('child-shown', 'shown-val'),
          ],
        ),
      );
      await tester.pump();

      // The hidden child's name label is suppressed.
      expect(find.text('Secret Child'), findsNothing);
      // The sibling that did NOT opt out still shows its name — proves the
      // toggle is per-field, not inherited group-wide.
      expect(find.text('Shown Child'), findsOneWidget);
      // The hidden child's name is still announced for accessibility.
      expect(find.bySemanticsLabel(RegExp('Secret Child')), findsWidgets);

      semanticsHandle.dispose();
    },
  );

  testWidgets('grouped long text child shows its label by default', (
    tester,
  ) async {
    final group = CustomField(
      id: 'grp-long',
      name: 'Notes Group',
      fieldType: CustomFieldType.text,
      fieldTypeId: 'group',
      createdAt: DateTime(2026, 1, 1),
      typeConfig: const GroupConfig(),
    );
    final longTextChild = CustomField(
      id: 'child-long',
      name: 'Detailed Notes',
      fieldType: CustomFieldType.longText,
      fieldTypeId: 'long_text',
      parentFieldId: 'grp-long',
      displayOrder: 0,
      createdAt: DateTime(2026, 1, 1),
      typeConfig: const LongTextConfig(),
    );

    await tester.pumpWidget(
      subject(
        fields: [group, longTextChild],
        values: [value('child-long', 'Line one\nLine two')],
      ),
    );
    await tester.pump();

    expect(find.text('Detailed Notes'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
  });

  testWidgets('an empty group reserves no space between its neighbors', (
    tester,
  ) async {
    // A group whose only child has no value renders nothing. It must not
    // leave a phantom gap: total height with the empty group present must
    // equal the height without it.
    final before = CustomField(
      id: 'a',
      name: 'Before',
      fieldType: CustomFieldType.longText,
      createdAt: DateTime(2026, 1, 1),
    );
    final group = CustomField(
      id: 'g',
      name: 'Empty Group',
      fieldType: CustomFieldType.text,
      fieldTypeId: 'group',
      typeConfig: const GroupConfig(),
      createdAt: DateTime(2026, 1, 1),
    );
    final groupChild = CustomField(
      id: 'gc',
      name: 'Child',
      fieldType: CustomFieldType.text,
      parentFieldId: 'g',
      createdAt: DateTime(2026, 1, 1),
    );
    final after = CustomField(
      id: 'b',
      name: 'After',
      fieldType: CustomFieldType.longText,
      createdAt: DateTime(2026, 1, 1),
    );
    final values = [value('a', 'aa'), value('b', 'bb')];

    await tester.pumpWidget(
      subject(fields: [before, group, groupChild, after], values: values),
    );
    await tester.pump();
    final withGroup = tester.getSize(find.byType(CustomFieldsDisplay)).height;

    await tester.pumpWidget(subject(fields: [before, after], values: values));
    await tester.pump();
    final withoutGroup = tester
        .getSize(find.byType(CustomFieldsDisplay))
        .height;

    expect(withGroup, withoutGroup);
  });

  // ── N-color gradient render seam tests ─────────────────────────────────────

  test('resolveTrackColors: 4-color gradientColorsHex resolves to 4 colors', () {
    const config = SliderConfig(
      mode: SliderMode.labeled,
      gradientColorsHex: ['#FF0000', '#00FF00', '#0000FF', '#FFFF00'],
    );
    final colors = resolveTrackColorsForTest(config);
    expect(colors, isNotNull);
    expect(colors!.length, 4);
  });

  test('resolveTrackColors: empty gradientColorsHex falls through to legacy', () {
    const config = SliderConfig(
      mode: SliderMode.labeled,
      gradientColorsHex: [],
      leftColorHex: '#FF0000',
      rightColorHex: '#0000FF',
    );
    final colors = resolveTrackColorsForTest(config);
    // Must fall through to legacy left/right, not produce an empty list.
    expect(colors, isNotNull);
    expect(colors!.length, 2);
  });

  test(
    'resolveTrackColors: empty gradientColorsHex with no legacy hex returns null',
    () {
      const config = SliderConfig(
        mode: SliderMode.labeled,
        gradientColorsHex: [],
      );
      final colors = resolveTrackColorsForTest(config);
      expect(colors, isNull);
    },
  );

  test(
    'resolveTrackColors: single-element gradientColorsHex falls through to legacy',
    () {
      const config = SliderConfig(
        mode: SliderMode.labeled,
        gradientColorsHex: ['#FF0000'],
        leftColorHex: '#00FF00',
        rightColorHex: '#0000FF',
      );
      final colors = resolveTrackColorsForTest(config);
      // Single-element is not a valid gradient; must fall through to legacy.
      expect(colors, isNotNull);
      expect(colors!.length, 2);
    },
  );

  test(
    'resolveTrackColors: preset is authoritative even when gradientColorsHex is set',
    () {
      // 'sad-happy' preset is blue → yellow (2-color, no center).
      const config = SliderConfig(
        mode: SliderMode.labeled,
        gradientPresetId: 'sad-happy',
        gradientColorsHex: ['#FF0000', '#00FF00', '#0000FF', '#FFFF00'],
      );
      final colors = resolveTrackColorsForTest(config);
      // Must produce exactly 2 colors from the preset, not 4 from the hex list.
      expect(colors, isNotNull);
      expect(colors!.length, 2);
    },
  );

  test(
    'sameTrackColors: changing only an interior color returns false (repaint fires)',
    () {
      const r = Color(0xFFFF0000);
      const g = Color(0xFF00FF00);
      const b = Color(0xFF0000FF);
      const y = Color(0xFFFFFF00);

      final colorsA = [r, g, b, y];
      final colorsB = [r, Color(0xFF123456), b, y]; // only interior changed

      expect(sameTrackColorsForTest(colorsA, colorsA), isTrue);
      expect(sameTrackColorsForTest(colorsA, colorsB), isFalse);
    },
  );

  test('sameTrackColors: null inputs behave correctly', () {
    expect(sameTrackColorsForTest(null, null), isTrue);
    expect(sameTrackColorsForTest(null, [const Color(0xFFFF0000)]), isFalse);
    expect(sameTrackColorsForTest([const Color(0xFFFF0000)], null), isFalse);
  });
}

TextSpan? _findTextSpanWithPlainText(WidgetTester tester, String text) {
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    final span = richText.text;
    if (span is TextSpan && span.toPlainText() == text) return span;
  }
  return null;
}

TextSpan? _spanForText(TextSpan root, String text) {
  for (final span in _flatten(root)) {
    if (span.text == text) return span;
  }
  return null;
}

Iterable<TextSpan> _flatten(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _flatten(child);
    }
  }
}

bool _hasRichTextContaining(WidgetTester tester, String text) {
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    if (richText.text.toPlainText().contains(text)) return true;
  }
  return false;
}

Future<void> _expectStaticSliderPaintGeometry(
  WidgetTester tester, {
  required SliderConfig config,
  required double value,
  required String indicatorLabel,
  required RRect expectedTrackRRect,
  required RRect expectedThumbRRect,
  required List<Offset> expectedTickCenters,
  required double expectedTickRadius,
  int? expectedTickCount,
}) async {
  final sliderKey = GlobalKey();
  const sliderWidth = 320;
  const sliderHeight = 48;

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            key: sliderKey,
            width: sliderWidth.toDouble(),
            height: sliderHeight.toDouble(),
            child: buildSliderDisplayPixelHarness(
              config: config,
              value: value,
              indicatorLabel: indicatorLabel,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));

  expect(
    find.byKey(sliderKey),
    paintsExactlyCountTimes(
      #drawCircle,
      expectedTickCount ?? expectedTickCenters.length,
    ),
  );

  final pattern = paints..something(_rrectPaint(expectedTrackRRect));
  for (final tickCenter in expectedTickCenters) {
    pattern.something(_circlePaint(tickCenter, radius: expectedTickRadius));
  }
  pattern
    ..something(_rrectPaint(expectedThumbRRect))
    ..something(
      _rrectPaint(
        expectedThumbRRect,
        strokeWidth: 1,
        style: PaintingStyle.stroke,
      ),
    );

  expect(find.byKey(sliderKey), pattern);
}

PaintPatternPredicate _circlePaint(Offset expected, {required double radius}) {
  return (methodName, arguments) {
    if (methodName != #drawCircle) return false;
    return _offsetCloseTo(arguments[0] as Offset, expected) &&
        _doubleCloseTo(arguments[1] as double, radius);
  };
}

PaintPatternPredicate _rrectPaint(
  RRect expected, {
  double? strokeWidth,
  PaintingStyle? style,
}) {
  return (methodName, arguments) {
    if (methodName != #drawRRect) return false;
    if (!_rrectCloseTo(arguments.first as RRect, expected)) return false;
    final paint = arguments[1] as Paint;
    return (strokeWidth == null || paint.strokeWidth == strokeWidth) &&
        (style == null || paint.style == style);
  };
}

bool _offsetCloseTo(Offset actual, Offset expected) =>
    _doubleCloseTo(actual.dx, expected.dx) &&
    _doubleCloseTo(actual.dy, expected.dy);

bool _rrectCloseTo(RRect actual, RRect expected) =>
    _doubleCloseTo(actual.left, expected.left) &&
    _doubleCloseTo(actual.top, expected.top) &&
    _doubleCloseTo(actual.right, expected.right) &&
    _doubleCloseTo(actual.bottom, expected.bottom) &&
    _doubleCloseTo(actual.tlRadiusX, expected.tlRadiusX) &&
    _doubleCloseTo(actual.tlRadiusY, expected.tlRadiusY) &&
    _doubleCloseTo(actual.trRadiusX, expected.trRadiusX) &&
    _doubleCloseTo(actual.trRadiusY, expected.trRadiusY) &&
    _doubleCloseTo(actual.blRadiusX, expected.blRadiusX) &&
    _doubleCloseTo(actual.blRadiusY, expected.blRadiusY) &&
    _doubleCloseTo(actual.brRadiusX, expected.brRadiusX) &&
    _doubleCloseTo(actual.brRadiusY, expected.brRadiusY);

bool _doubleCloseTo(double actual, double expected) =>
    (actual - expected).abs() < 0.05;

String _fieldTypeIdFor(CustomFieldType type) => switch (type) {
  CustomFieldType.text => 'text',
  CustomFieldType.color => 'color',
  CustomFieldType.date => 'date',
  CustomFieldType.longText => 'long_text',
  CustomFieldType.choice => 'choice',
};
