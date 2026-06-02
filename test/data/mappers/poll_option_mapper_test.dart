import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/data/mappers/poll_option_mapper.dart';

void main() {
  group('PollOptionMapper.toDomain colorHex normalization', () {
    db.PollOption row({String? colorHex}) => db.PollOption(
      id: 'opt-1',
      pollId: 'poll-1',
      optionText: 'Yes',
      sortOrder: 0,
      isOtherOption: false,
      colorHex: colorHex,
      isDeleted: false,
    );

    test('passes a bare RRGGBB hex through unchanged', () {
      final model = PollOptionMapper.toDomain(row(colorHex: 'EF4444'));
      expect(model.colorHex, 'EF4444');
    });

    test('strips a leading # so bare-hex render sites never throw', () {
      final model = PollOptionMapper.toDomain(row(colorHex: '#EF4444'));
      expect(model.colorHex, 'EF4444');
      // Poll render sites parse with int.parse('FF$hex', radix: 16); a stray
      // '#' (from imports, older builds, or a peer on another version) used to
      // throw a FormatException there. Prove it parses cleanly now.
      expect(
        () => int.parse('FF${model.colorHex}', radix: 16),
        returnsNormally,
      );
    });

    test('leaves null untouched', () {
      final model = PollOptionMapper.toDomain(row(colorHex: null));
      expect(model.colorHex, isNull);
    });

    test('maps the remaining fields alongside the color', () {
      final model = PollOptionMapper.toDomain(
        const db.PollOption(
          id: 'opt-9',
          pollId: 'poll-9',
          optionText: 'Maybe',
          sortOrder: 3,
          isOtherOption: true,
          colorHex: '22C55E',
          isDeleted: false,
        ),
      );
      expect(model.id, 'opt-9');
      expect(model.text, 'Maybe');
      expect(model.sortOrder, 3);
      expect(model.isOtherOption, isTrue);
      expect(model.colorHex, '22C55E');
    });
  });
}
