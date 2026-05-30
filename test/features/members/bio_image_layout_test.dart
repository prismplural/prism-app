import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/services/bio_image_layout.dart';
import 'package:prism_plurality/features/members/services/bio_image_size.dart';

void main() {
  group('isBlockImageSize', () {
    test('percent and unsized are block', () {
      expect(isBlockImageSize(BioImageSize.parse('50%')), isTrue);
      expect(isBlockImageSize(BioImageSize.parse('100%')), isTrue);
      expect(isBlockImageSize(BioImageSize.unset), isTrue);
    });

    test('small explicit sizes are inline', () {
      expect(isBlockImageSize(BioImageSize.parse('16')), isFalse);
      expect(isBlockImageSize(BioImageSize.parse('32')), isFalse);
      expect(isBlockImageSize(BioImageSize.parse('47')), isFalse);
      expect(isBlockImageSize(BioImageSize.parse('x40')), isFalse);
    });

    test('at/above the threshold is block (either dimension)', () {
      expect(isBlockImageSize(BioImageSize.parse('48')), isTrue);
      expect(isBlockImageSize(BioImageSize.parse('96')), isTrue);
      expect(isBlockImageSize(BioImageSize.parse('200')), isTrue);
      expect(isBlockImageSize(BioImageSize.parse('120x40')), isTrue); // w≥48
      expect(isBlockImageSize(BioImageSize.parse('30x80')), isTrue); // h≥48
    });
  });

  group('blockifyImageMarkdown', () {
    test('returns text without images unchanged', () {
      const t = 'just some words, no images at all';
      expect(blockifyImageMarkdown(t), t);
    });

    test('leaves a small inline image in place', () {
      const t = 'a flag ![](flag#20) inline here';
      expect(blockifyImageMarkdown(t), t);
    });

    test('promotes a large image to its own paragraph', () {
      expect(
        blockifyImageMarkdown('before ![](flag#96) after'),
        'before\n\n![](flag#96)\n\nafter',
      );
    });

    test('promotes a percent image to its own paragraph', () {
      expect(
        blockifyImageMarkdown('before ![](flag#50%) after'),
        'before\n\n![](flag#50%)\n\nafter',
      );
    });

    test('promotes an unsized image to its own paragraph', () {
      expect(
        blockifyImageMarkdown('before ![](flag) after'),
        'before\n\n![](flag)\n\nafter',
      );
    });

    test('mixed: only the large one is promoted, small stays inline', () {
      expect(
        blockifyImageMarkdown('a ![](flag#16) b ![](flag#96) c'),
        'a ![](flag#16) b\n\n![](flag#96)\n\nc',
      );
    });

    test('does not pile up blank lines around an already-isolated image', () {
      expect(
        blockifyImageMarkdown('text\n\n![](flag#100%)\n\nmore'),
        'text\n\n![](flag#100%)\n\nmore',
      );
    });

    test('trims when the image is the whole input', () {
      expect(blockifyImageMarkdown('![](flag#100%)'), '![](flag#100%)');
    });

    test('leaves images inside a table row untouched (side-by-side layout)', () {
      const table = '| ![](flag#96) | some text beside it |\n'
          '| --- | --- |\n'
          '| ![](flag#50%) | more text |';
      // Block-eligible images, but inside table rows → must not be promoted
      // (a blank line mid-row would break the table).
      expect(blockifyImageMarkdown(table), table);
    });

    test('promotes a block image in prose but not the one in an adjacent table',
        () {
      const input = 'intro ![](flag#96) text\n'
          '| ![](flag#96) | beside |\n'
          '| --- | --- |';
      expect(
        blockifyImageMarkdown(input),
        'intro\n\n![](flag#96)\n\ntext\n'
            '| ![](flag#96) | beside |\n'
            '| --- | --- |',
      );
    });
  });
}
