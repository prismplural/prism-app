import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/services/remote_markdown_image_refs.dart';

void main() {
  group('remote markdown image refs', () {
    test('finds external markdown image URLs', () {
      final refs = findRemoteMarkdownImageRefs(
        'Before ![Cat](https://cdn.example.com/cat-photo.png#50%) '
        'and ![](http://example.com/banner.webp).',
      );

      expect(refs, hasLength(2));
      expect(refs[0].altText, 'Cat');
      expect(refs[0].url, 'https://cdn.example.com/cat-photo.png');
      expect(refs[0].fragment, '#50%');
      expect(refs[1].altText, '');
      expect(refs[1].url, 'http://example.com/banner.webp');
      expect(refs[1].fragment, '');
    });

    test('finds URL-like markdown images without an explicit scheme', () {
      final refs = findRemoteMarkdownImageRefs(
        '![Blinkie](i.postimg.cc/abc/blinkie.gif) '
        '![](//cdn.example.com/stamp.png#2em)',
      );

      expect(refs, hasLength(2));
      expect(refs[0].altText, 'Blinkie');
      expect(refs[0].url, 'i.postimg.cc/abc/blinkie.gif');
      expect(refs[0].fragment, '');
      expect(refs[1].url, '//cdn.example.com/stamp.png');
      expect(refs[1].fragment, '#2em');
    });

    test('leaves bare library tags out of remote image detection', () {
      expect(findRemoteMarkdownImageRefs('![Flag](nbflag)'), isEmpty);
      expect(hasStageableMarkdownImageRefs('![Flag](nbflag)'), isFalse);
    });

    test('finds uppercase URL schemes and markdown image titles', () {
      final refs = findRemoteMarkdownImageRefs(
        '![Stamp](HTTPS://cdn.example.com/stamp.png "A stamp")',
      );

      expect(refs, hasLength(1));
      expect(refs.single.altText, 'Stamp');
      expect(refs.single.url, 'HTTPS://cdn.example.com/stamp.png');
      expect(refs.single.fragment, '');
      expect(refs.single.titleSuffix, ' "A stamp"');
      expect(
        rewriteRemoteMarkdownImageRefs(
          '![Stamp](HTTPS://cdn.example.com/stamp.png "A stamp")',
          {'HTTPS://cdn.example.com/stamp.png': 'stamp'},
        ),
        '![Stamp](stamp "A stamp")',
      );
    });

    test('finds embedded data image markdown refs', () {
      final refs = findDataMarkdownImageRefs(
        'Before ![Flag](data:image/png;base64,aGVsbG8=) after.',
      );

      expect(refs, hasLength(1));
      expect(refs[0].altText, 'Flag');
      expect(refs[0].mimeType, 'image/png');
      expect(utf8.decode(decodeDataMarkdownImageRef(refs[0])), 'hello');
    });

    test('decodes embedded data image refs with unpadded base64', () {
      final refs = findDataMarkdownImageRefs(
        '![Flag](data:image/png;base64,aGVsbG8)',
      );

      expect(refs, hasLength(1));
      expect(utf8.decode(decodeDataMarkdownImageRef(refs.single)), 'hello');
    });

    test('finds embedded data image refs case-insensitively', () {
      final refs = findDataMarkdownImageRefs(
        '![Flag](DATA:IMAGE/PNG;base64,aGVsbG8=)',
      );

      expect(refs, hasLength(1));
      expect(refs.single.mimeType, 'IMAGE/PNG');
      expect(utf8.decode(decodeDataMarkdownImageRef(refs.single)), 'hello');
    });

    test('reports stageable refs for remote or embedded images', () {
      expect(
        hasStageableMarkdownImageRefs(
          '![remote](https://example.com/flag.png)',
        ),
        isTrue,
      );
      expect(
        hasStageableMarkdownImageRefs('![remote](http://example.com/flag.png)'),
        isTrue,
      );
      expect(
        hasStageableMarkdownImageRefs('![remote](i.postimg.cc/x/flag.png)'),
        isTrue,
      );
      expect(
        hasStageableMarkdownImageRefs('![inline](data:image/png;base64,AA==)'),
        isTrue,
      );
      expect(hasStageableMarkdownImageRefs('![library](flag-tag)'), isFalse);
    });

    test('builds imports for embedded images with unique tags', () {
      final refs = findDataMarkdownImageRefs(
        '![](data:image/png;base64,AA==) ![](data:image/png;base64,AQ==)',
      );

      final imports = buildDataMarkdownImageImports(
        refs,
        unavailableTags: const ['embedded-image-1'],
      );

      expect(imports, hasLength(2));
      expect(imports[0].suggestedTag, 'embedded-image-1-2');
      expect(imports[1].suggestedTag, 'embedded-image-2');
    });

    test('dedupes identical embedded refs and rewrites every occurrence', () {
      const embedded = '![Flag](data:image/png;base64,AA==)';
      final refs = findDataMarkdownImageRefs('$embedded then $embedded');

      final imports = buildDataMarkdownImageImports(refs);

      expect(imports, hasLength(1));
      expect(imports.single.ref.fullMatch, embedded);
      expect(
        rewriteDataMarkdownImageRefs('$embedded then $embedded', {
          embedded: '![Flag](flag)',
        }),
        '![Flag](flag) then ![Flag](flag)',
      );
    });

    test('rewrites embedded image refs to committed library tags', () {
      const first = '![Flag](data:image/png;base64,AA==)';
      const second = '![](data:image/jpeg;base64,AQ==)';
      const markdown = '$first between $second';

      final rewritten = rewriteDataMarkdownImageRefs(markdown, {
        first: '![Flag](flag)',
        second: '![](flag-2)',
      });

      expect(rewritten, '![Flag](flag) between ![](flag-2)');
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
      'rewrites only successfully imported URLs and preserves alt/fragment/title',
      () {
        const markdown =
            '![Cat](https://example.com/cat.png#50% "Cat title") ![Dog](https://example.com/dog.png)';

        final rewritten = rewriteRemoteMarkdownImageRefs(markdown, {
          'https://example.com/cat.png': 'cat-photo',
        });

        expect(
          rewritten,
          '![Cat](cat-photo#50% "Cat title") ![Dog](https://example.com/dog.png)',
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
