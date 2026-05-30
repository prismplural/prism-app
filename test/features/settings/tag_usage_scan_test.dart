import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/settings/utils/tag_usage_scan.dart';

void main() {
  group('scanTagUsage', () {
    test('always returns an entry for every tag (unused = empty list)', () {
      final usage = scanTagUsage(
        tags: {'nbflag', 'divider'},
        sources: const [],
      );
      expect(usage.keys, containsAll(<String>['nbflag', 'divider']));
      expect(usage['nbflag'], isEmpty);
      expect(usage['divider'], isEmpty);
    });

    test('records a source that references a tag, with kind/label/route', () {
      final usage = scanTagUsage(
        tags: {'nbflag'},
        sources: const [
          TagUsageSource(
            text: 'intro ![](nbflag) outro',
            kind: TagUsageKind.bio,
            label: "Alex's bio",
            route: '/members/m1',
          ),
          TagUsageSource(
            text: 'no images here',
            kind: TagUsageKind.note,
            label: 'a note',
            route: '/notes/n1',
          ),
        ],
      );
      expect(usage['nbflag'], hasLength(1));
      final ref = usage['nbflag']!.single;
      expect(ref.kind, TagUsageKind.bio);
      expect(ref.label, "Alex's bio");
      expect(ref.route, '/members/m1');
    });

    test('strips a #WxH / #% sizing fragment before matching', () {
      final usage = scanTagUsage(
        tags: {'nbflag'},
        sources: const [
          TagUsageSource(
            text: '![](nbflag#200x80)',
            kind: TagUsageKind.bio,
            label: "Alex's bio",
            route: '/members/m1',
          ),
          TagUsageSource(
            text: '![](nbflag#50%)',
            kind: TagUsageKind.group,
            label: 'Crew',
            route: '/groups/g1',
          ),
        ],
      );
      expect(usage['nbflag']!.map((r) => r.route), ['/members/m1', '/groups/g1']);
    });

    test('credits a source only once even if it references the tag twice', () {
      final usage = scanTagUsage(
        tags: {'nbflag'},
        sources: const [
          TagUsageSource(
            text: '![](nbflag) and again ![](nbflag)',
            kind: TagUsageKind.note,
            label: 'a note',
            route: '/notes/n1',
          ),
        ],
      );
      expect(usage['nbflag'], hasLength(1));
    });

    test('records one entry per chat message referencing the tag', () {
      final usage = scanTagUsage(
        tags: {'nbflag'},
        sources: const [
          TagUsageSource(
            text: '![](nbflag)',
            kind: TagUsageKind.chat,
            label: 'Chat message',
            route: '/chat/c1?messageId=msg1',
          ),
          TagUsageSource(
            text: 'hi ![](nbflag)',
            kind: TagUsageKind.chat,
            label: 'Chat message',
            route: '/chat/c1?messageId=msg2',
          ),
        ],
      );
      expect(usage['nbflag'], hasLength(2));
      expect(
        usage['nbflag']!.map((r) => r.route),
        ['/chat/c1?messageId=msg1', '/chat/c1?messageId=msg2'],
      );
    });

    test('ignores refs that are not library tags', () {
      final usage = scanTagUsage(
        tags: {'nbflag'},
        sources: const [
          TagUsageSource(
            text: '![](https://example.com/x.png) ![](someothertag)',
            kind: TagUsageKind.bio,
            label: "Alex's bio",
            route: '/members/m1',
          ),
        ],
      );
      expect(usage['nbflag'], isEmpty);
    });
  });

  group('rewriteImageTag', () {
    test('preserves alt text', () {
      expect(
        rewriteImageTag('![my flag](flag)', 'flag', 'banner'),
        '![my flag](banner)',
      );
    });

    test('preserves #WxH sizing fragment', () {
      expect(
        rewriteImageTag('![](flag#50x80)', 'flag', 'banner'),
        '![](banner#50x80)',
      );
    });

    test('preserves #percent sizing fragment', () {
      expect(
        rewriteImageTag('![alt](flag#50%)', 'flag', 'banner'),
        '![alt](banner#50%)',
      );
    });

    test('rewrites multiple occurrences in one blob', () {
      expect(
        rewriteImageTag(
          'intro ![](flag) middle ![a](flag#100x100) end ![b](flag)',
          'flag',
          'banner',
        ),
        'intro ![](banner) middle ![a](banner#100x100) end ![b](banner)',
      );
    });

    test('does NOT match a longer tag with oldTag as a prefix', () {
      expect(
        rewriteImageTag('![](flagpole)', 'flag', 'banner'),
        '![](flagpole)',
      );
      // Mixed: only the exact `flag` ref is rewritten, `flagpole` untouched.
      expect(
        rewriteImageTag('![](flag) and ![](flagpole)', 'flag', 'banner'),
        '![](banner) and ![](flagpole)',
      );
    });

    test('does NOT match a prefix-of-oldTag fragment (e.g. fla)', () {
      expect(
        rewriteImageTag('![](fla)', 'flag', 'banner'),
        '![](fla)',
      );
    });

    test('returns non-matching text unchanged', () {
      const text = 'no images here, just ![](othertag) and text';
      expect(rewriteImageTag(text, 'flag', 'banner'), text);
    });

    test('returns text without any markdown image unchanged', () {
      const text = 'plain text with flag word but no image';
      expect(rewriteImageTag(text, 'flag', 'banner'), text);
    });

    test('escapes regex metacharacters in oldTag', () {
      expect(
        rewriteImageTag('![](a.b+c)', 'a.b+c', 'newtag'),
        '![](newtag)',
      );
      // The metachar tag must not match a different literal string.
      expect(
        rewriteImageTag('![](axbxc)', 'a.b+c', 'newtag'),
        '![](axbxc)',
      );
    });
  });

  group('textReferencesTag', () {
    test('true for exact tag ref with and without fragment', () {
      expect(textReferencesTag('![](flag)', 'flag'), isTrue);
      expect(textReferencesTag('![alt](flag#50%)', 'flag'), isTrue);
    });

    test('false for prefix tags and non-matching text', () {
      expect(textReferencesTag('![](flagpole)', 'flag'), isFalse);
      expect(textReferencesTag('no images', 'flag'), isFalse);
      expect(textReferencesTag('![](othertag)', 'flag'), isFalse);
    });
  });
}
