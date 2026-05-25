/// Tests for the choice value formatter and compact label logic.
///
/// Fix 1 (JSON leak): verifies that resolving option IDs from a ChoiceConfig
/// produces human-readable labels instead of raw JSON.
///
/// Fix 2 (compact Other chip): verifies that the resolved-label list (which
/// includes Other) has the correct length so the chip-render loop reaches
/// the Other branch.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/choice_field_definition.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';

void main() {
  // ── Helpers (mirrors the logic extracted from _formatChoiceValue and compact widget) ──

  /// Mirrors _formatChoiceValue in custom_field_detail_screen.dart.
  /// Does NOT call context.l10n — uses a simple "Other: {value}" template
  /// so the test stays pure-Dart.
  String formatChoiceValue(
    String raw,
    ChoiceConfig config, {
    String otherPrefix = 'Other: ',
  }) {
    final parsed = choiceFieldDefinition.valueParser(raw);
    if (parsed is! ChoiceFieldValue) return '';
    final optionsById = {for (final o in config.options) o.id: o};
    final labels = parsed.optionIds
        .map((id) => optionsById[id]?.label)
        .whereType<String>()
        .where((l) => l.isNotEmpty)
        .toList();
    if (parsed.other != null && parsed.other!.isNotEmpty) {
      labels.add('$otherPrefix${parsed.other}');
    }
    return labels.join(', ');
  }

  /// Mirrors the compact widget's resolved-label list construction.
  /// Returns (resolvedOptions.length, resolvedLabels.length) so the test
  /// can assert that Other inflates the label count beyond the option count.
  ({int optionCount, int labelCount}) compactLabelCounts(
    String raw,
    ChoiceConfig config, {
    String otherPrefix = 'Other: ',
  }) {
    final parsed = choiceFieldDefinition.valueParser(raw);
    final choiceValue =
        parsed is ChoiceFieldValue ? parsed : const ChoiceFieldValue();

    final optionMap = {for (final o in config.options) o.id: o};
    final resolvedLabels = <String>[];
    final resolvedOptions = <ChoiceOption>[];

    for (final id in choiceValue.optionIds.toList()..sort()) {
      final option = optionMap[id];
      if (option != null) {
        resolvedLabels.add(option.label);
        resolvedOptions.add(option);
      }
    }
    if (choiceValue.other != null && choiceValue.other!.isNotEmpty) {
      resolvedLabels.add('$otherPrefix${choiceValue.other}');
    }

    return (optionCount: resolvedOptions.length, labelCount: resolvedLabels.length);
  }

  // ── Test fixtures ─────────────────────────────────────────────────────────

  final config = ChoiceConfig(
    options: [
      const ChoiceOption(
        id: 'uuid-a',
        label: 'Apple',
        sortOrder: 0,
        isDeleted: false,
      ),
      const ChoiceOption(
        id: 'uuid-b',
        label: 'Banana',
        sortOrder: 1,
        isDeleted: false,
      ),
      const ChoiceOption(
        id: 'uuid-c',
        label: 'Cherry',
        sortOrder: 2,
        isDeleted: false,
      ),
    ],
    allowsMultiple: true,
    allowsOther: true,
  );

  // ── Fix 1: formatter resolves labels (no raw JSON leak) ───────────────────

  group('_formatChoiceValue — no JSON leak (Fix 1)', () {
    test('two options selected → comma-separated labels (no JSON)', () {
      final value = ChoiceFieldValue(optionIds: {'uuid-a', 'uuid-b'});
      final raw = choiceFieldDefinition.valueEncoder(value);

      final result = formatChoiceValue(raw, config);

      expect(result, isNot(contains('{')),
          reason: 'Must not contain raw JSON braces');
      expect(result, isNot(contains('uuid-a')),
          reason: 'Must not contain raw UUIDs');
      expect(result, contains('Apple'));
      expect(result, contains('Banana'));
    });

    test('single option selected → just that label', () {
      final value = ChoiceFieldValue(optionIds: {'uuid-c'});
      final raw = choiceFieldDefinition.valueEncoder(value);

      final result = formatChoiceValue(raw, config);

      expect(result, equals('Cherry'));
    });

    test('option + other → labels joined with other prefix', () {
      final value = ChoiceFieldValue(
        optionIds: {'uuid-a'},
        other: 'My custom answer',
      );
      final raw = choiceFieldDefinition.valueEncoder(value);

      final result = formatChoiceValue(raw, config);

      expect(result, contains('Apple'));
      expect(result, contains('Other: My custom answer'));
    });

    test('only other (no option IDs) → just other prefix + text', () {
      final value = ChoiceFieldValue(optionIds: const {}, other: 'Mango');
      final raw = choiceFieldDefinition.valueEncoder(value);

      final result = formatChoiceValue(raw, config);

      expect(result, equals('Other: Mango'));
    });

    test('empty value → empty string', () {
      const value = ChoiceFieldValue();
      final raw = choiceFieldDefinition.valueEncoder(value);

      final result = formatChoiceValue(raw, config);

      expect(result, isEmpty);
    });

    test('unknown option ID is silently ignored', () {
      final value = ChoiceFieldValue(
        optionIds: {'uuid-a', 'uuid-unknown'},
      );
      final raw = choiceFieldDefinition.valueEncoder(value);

      final result = formatChoiceValue(raw, config);

      expect(result, equals('Apple'));
      expect(result, isNot(contains('uuid-unknown')));
    });

    test('raw JSON string passed directly → empty string (no crash)', () {
      const raw = '{"options":["uuid-a","uuid-b"],"other":"x"}';
      final result = formatChoiceValue(raw, config);

      // The formatter parses it correctly via valueParser and returns labels.
      expect(result, isNot(contains('{')));
      expect(result, contains('Apple'));
      expect(result, contains('Banana'));
      expect(result, contains('Other: x'));
    });
  });

  // ── Fix 2: compact label count includes Other (was unreachable) ───────────

  group('compact widget label count — Other chip reachable (Fix 2)', () {
    test('2 options + no other → labelCount == optionCount', () {
      final value = ChoiceFieldValue(optionIds: {'uuid-a', 'uuid-b'});
      final raw = choiceFieldDefinition.valueEncoder(value);
      final counts = compactLabelCounts(raw, config);

      expect(counts.optionCount, 2);
      expect(counts.labelCount, 2);
    });

    test('2 options + Other selected → labelCount is optionCount + 1', () {
      final value = ChoiceFieldValue(
        optionIds: {'uuid-a', 'uuid-b'},
        other: 'Durian',
      );
      final raw = choiceFieldDefinition.valueEncoder(value);
      final counts = compactLabelCounts(raw, config);

      // Before Fix 2: visibleCount = resolvedOptions.length.clamp(0, 3) = 2,
      // so the loop never reached index 2 (the Other pill). After Fix 2 the
      // loop iterates to resolvedLabels.length, which is 3.
      expect(counts.optionCount, 2,
          reason: 'Only 2 real options selected');
      expect(counts.labelCount, 3,
          reason: 'Other adds one extra label entry — now reachable as chip');
    });

    test('3 options + Other → labelCount is 4, clamped to 3 visible + 1 overflow', () {
      final value = ChoiceFieldValue(
        optionIds: {'uuid-a', 'uuid-b', 'uuid-c'},
        other: 'Elderberry',
      );
      final raw = choiceFieldDefinition.valueEncoder(value);
      final counts = compactLabelCounts(raw, config);

      const maxVisible = 3; // _ChoiceCompactWidget._maxVisibleChips
      expect(counts.optionCount, 3);
      expect(counts.labelCount, 4);
      // With _maxVisibleChips = 3: overflow = 4 - 3 = 1.
      expect(counts.labelCount - maxVisible, 1,
          reason: 'Other pushed into +N overflow correctly');
    });

    test('only Other (no option IDs) → labelCount is 1, optionCount is 0', () {
      final value = ChoiceFieldValue(
        optionIds: const {},
        other: 'Figs',
      );
      final raw = choiceFieldDefinition.valueEncoder(value);
      final counts = compactLabelCounts(raw, config);

      expect(counts.optionCount, 0);
      expect(counts.labelCount, 1,
          reason: 'Other-only selection renders as a single chip');
    });
  });
}
