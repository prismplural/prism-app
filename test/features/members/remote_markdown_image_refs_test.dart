import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/services/remote_markdown_image_refs.dart';

void main() {
  group('remote markdown image refs', () {
    test('finds https markdown image URLs', () {
      final refs = findRemoteMarkdownImageRefs(
        'Before ![Cat](https://cdn.example.com/cat-photo.png#50%) '
        'and ![](http://example.com/banner.webp).',
      );

      expect(refs, hasLength(1));
      expect(refs[0].altText, 'Cat');
      expect(refs[0].url, 'https://cdn.example.com/cat-photo.png');
      expect(refs[0].fragment, '#50%');
    });

    test('suggests tags from filenames', () {
      expect(
        suggestedRemoteImageTag(
          'https://cdn.example.com/path/My%20Cool_Image.PNG?token=abc',
        ),
        'My-Cool_Image',
      );
      expect(suggestedRemoteImageTag('https://example.com/'), 'image');
    });

    test('dedupes URLs and avoids unavailable tags', () {
      final refs = findRemoteMarkdownImageRefs(
        '![](https://example.com/cat.png) ![](https://example.com/cat.png#50%) '
        '![](https://example.com/dog.png)',
      );

      final imports = buildRemoteMarkdownImageImports(
        refs,
        unavailableTags: const ['cat'],
      );

      expect(imports, hasLength(2));
      expect(imports[0].url, 'https://example.com/cat.png');
      expect(imports[0].suggestedTag, 'cat-2');
      expect(imports[1].suggestedTag, 'dog');
    });

    test(
      'rewrites only successfully imported URLs and preserves alt/fragment',
      () {
        const markdown =
            '![Cat](https://example.com/cat.png#50%) ![Dog](https://example.com/dog.png)';

        final rewritten = rewriteRemoteMarkdownImageRefs(markdown, {
          'https://example.com/cat.png': 'cat-photo',
        });

        expect(
          rewritten,
          '![Cat](cat-photo#50%) ![Dog](https://example.com/dog.png)',
        );
      },
    );

    test('validates choices and preserves normalized tag case', () {
      final validation = validateRemoteMarkdownImageTagChoices({
        'https://example.com/cat.png': ' Cat Flag ',
      });

      expect(validation.isValid, isTrue);
      expect(validation.normalizedTags, {
        'https://example.com/cat.png': 'Cat-Flag',
      });
    });

    test('rejects choices with no usable tag characters', () {
      final validation = validateRemoteMarkdownImageTagChoices({
        'https://example.com/cat.png': ' )#?! ',
      });

      expect(validation.isValid, isFalse);
      expect(validation.errorMessage, 'Tag has no usable characters');
    });

    test('rejects exact-case duplicate choices', () {
      final validation = validateRemoteMarkdownImageTagChoices({
        'https://example.com/cat.png': 'Flag',
        'https://example.com/dog.png': 'Flag',
      });

      expect(validation.isValid, isFalse);
      expect(validation.errorMessage, 'Tag "Flag" is already in use');
    });

    test('checks unavailable tags case-sensitively', () {
      expect(
        validateRemoteMarkdownImageTagChoices(
          {'https://example.com/cat.png': 'Flag'},
          unavailableTags: const ['flag'],
        ).isValid,
        isTrue,
      );
      expect(
        validateRemoteMarkdownImageTagChoices(
          {'https://example.com/cat.png': 'Flag'},
          unavailableTags: const ['Flag'],
        ).errorMessage,
        'Tag "Flag" is already in use',
      );
    });
  });
}
