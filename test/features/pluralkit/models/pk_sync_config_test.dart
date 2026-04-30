import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';

void main() {
  // ── PkSyncDirection ───────────────────────────────────────────────────────

  group('PkSyncDirection', () {
    test('pullOnly has pullEnabled=true, pushEnabled=false', () {
      expect(PkSyncDirection.pullOnly.pullEnabled, isTrue);
      expect(PkSyncDirection.pullOnly.pushEnabled, isFalse);
    });

    test('pushOnly has pullEnabled=false, pushEnabled=true', () {
      expect(PkSyncDirection.pushOnly.pullEnabled, isFalse);
      expect(PkSyncDirection.pushOnly.pushEnabled, isTrue);
    });

    test('bidirectional has pullEnabled=true, pushEnabled=true', () {
      expect(PkSyncDirection.bidirectional.pullEnabled, isTrue);
      expect(PkSyncDirection.bidirectional.pushEnabled, isTrue);
    });

    test('disabled has pullEnabled=false, pushEnabled=false', () {
      expect(PkSyncDirection.disabled.pullEnabled, isFalse);
      expect(PkSyncDirection.disabled.pushEnabled, isFalse);
    });
  });

  // ── PkFieldSyncConfig JSON round-trip ─────────────────────────────────────

  group('PkFieldSyncConfig', () {
    test('JSON round-trip preserves all fields', () {
      const config = PkFieldSyncConfig(
        name: PkSyncDirection.pullOnly,
        pronouns: PkSyncDirection.pushOnly,
        description: PkSyncDirection.bidirectional,
        color: PkSyncDirection.disabled,
        proxyTags: PkSyncDirection.pushOnly,
      );

      final json = config.toJson();
      final restored = PkFieldSyncConfig.fromJson(json);

      expect(restored.name, PkSyncDirection.pullOnly);
      expect(restored.pronouns, PkSyncDirection.pushOnly);
      expect(restored.description, PkSyncDirection.bidirectional);
      expect(restored.color, PkSyncDirection.disabled);
      expect(restored.proxyTags, PkSyncDirection.pushOnly);
    });

    test('default values are bidirectional', () {
      const config = PkFieldSyncConfig();
      expect(config.name, PkSyncDirection.bidirectional);
      expect(config.pronouns, PkSyncDirection.bidirectional);
      expect(config.description, PkSyncDirection.bidirectional);
      expect(config.color, PkSyncDirection.bidirectional);
      expect(config.proxyTags, PkSyncDirection.bidirectional);
    });

    test(
      'proxyTags default is bidirectional by documented product policy (#36)',
      () {
        // Pinned: proxy tags are editable in Prism (see proxy_tags_section
        // in features/members/widgets/) and the product decision is that
        // local edits should propagate to PK and vice versa. Do not flip
        // this default to pull-only or disabled without re-deciding the
        // product behavior of the editable proxy-tag UI.
        const config = PkFieldSyncConfig();
        expect(config.proxyTags, PkSyncDirection.bidirectional);
      },
    );

    test('fromJson handles missing fields with defaults', () {
      final config = PkFieldSyncConfig.fromJson(<String, dynamic>{});
      expect(config.name, PkSyncDirection.bidirectional);
      expect(config.pronouns, PkSyncDirection.bidirectional);
      expect(config.description, PkSyncDirection.bidirectional);
      expect(config.color, PkSyncDirection.bidirectional);
      expect(config.proxyTags, PkSyncDirection.bidirectional);
    });

    test('directionFor returns correct direction for known fields', () {
      const config = PkFieldSyncConfig(
        name: PkSyncDirection.pullOnly,
        pronouns: PkSyncDirection.pushOnly,
        description: PkSyncDirection.disabled,
        color: PkSyncDirection.bidirectional,
        proxyTags: PkSyncDirection.pushOnly,
      );

      expect(config.directionFor('name'), PkSyncDirection.pullOnly);
      expect(config.directionFor('pronouns'), PkSyncDirection.pushOnly);
      expect(config.directionFor('description'), PkSyncDirection.disabled);
      expect(config.directionFor('color'), PkSyncDirection.bidirectional);
      expect(config.directionFor('proxyTags'), PkSyncDirection.pushOnly);
    });

    test('directionFor returns bidirectional for unknown fields', () {
      const config = PkFieldSyncConfig();
      expect(config.directionFor('unknown'), PkSyncDirection.bidirectional);
    });
  });

  // ── parseFieldSyncConfig ──────────────────────────────────────────────────

  group('parseFieldSyncConfig', () {
    test('null returns empty map', () {
      expect(parseFieldSyncConfig(null), isEmpty);
    });

    test('empty string returns empty map', () {
      expect(parseFieldSyncConfig(''), isEmpty);
    });

    test('invalid JSON returns empty map', () {
      expect(parseFieldSyncConfig('not json'), isEmpty);
    });

    test('valid JSON parses correctly', () {
      final json = jsonEncode({
        'member-1': {
          'name': 'pullOnly',
          'pronouns': 'pushOnly',
          'description': 'bidirectional',
          'color': 'disabled',
          'proxyTags': 'pushOnly',
        },
      });

      final result = parseFieldSyncConfig(json);
      expect(result.length, 1);
      expect(result['member-1']!.name, PkSyncDirection.pullOnly);
      expect(result['member-1']!.pronouns, PkSyncDirection.pushOnly);
      expect(result['member-1']!.description, PkSyncDirection.bidirectional);
      expect(result['member-1']!.color, PkSyncDirection.disabled);
      expect(result['member-1']!.proxyTags, PkSyncDirection.pushOnly);
    });
  });

  // ── serializeFieldSyncConfig ──────────────────────────────────────────────

  group('serializeFieldSyncConfig', () {
    test('output matches expected format', () {
      final config = {
        'member-1': const PkFieldSyncConfig(
          name: PkSyncDirection.pullOnly,
          pronouns: PkSyncDirection.pushOnly,
          description: PkSyncDirection.bidirectional,
          color: PkSyncDirection.disabled,
          proxyTags: PkSyncDirection.pullOnly,
        ),
      };

      final serialized = serializeFieldSyncConfig(config);
      final decoded = jsonDecode(serialized) as Map<String, dynamic>;

      expect(decoded.containsKey('member-1'), isTrue);
      final memberConfig = decoded['member-1'] as Map<String, dynamic>;
      expect(memberConfig['name'], 'pullOnly');
      expect(memberConfig['pronouns'], 'pushOnly');
      expect(memberConfig['description'], 'bidirectional');
      expect(memberConfig['color'], 'disabled');
      expect(memberConfig['proxyTags'], 'pullOnly');
    });

    test('round-trip: serialize then parse', () {
      final original = {
        'a': const PkFieldSyncConfig(
          name: PkSyncDirection.pullOnly,
          color: PkSyncDirection.disabled,
        ),
        'b': const PkFieldSyncConfig(),
      };

      final serialized = serializeFieldSyncConfig(original);
      final parsed = parseFieldSyncConfig(serialized);

      expect(parsed['a']!.name, PkSyncDirection.pullOnly);
      expect(parsed['a']!.color, PkSyncDirection.disabled);
      expect(parsed['b']!.name, PkSyncDirection.bidirectional);
    });
  });

  // ── PkSyncSummary ─────────────────────────────────────────────────────────

  group('PkSyncSummary', () {
    test('totalChanges calculation', () {
      const summary = PkSyncSummary(
        membersPulled: 3,
        membersPushed: 2,
        membersSkipped: 10,
        switchesPulled: 1,
        switchesPushed: 4,
      );

      // totalChanges = pulled + pushed + switchesPulled + switchesPushed
      // (does NOT include skipped)
      expect(summary.totalChanges, 3 + 2 + 1 + 4);
    });

    test('totalChanges is zero when no changes', () {
      const summary = PkSyncSummary(membersSkipped: 5);
      expect(summary.totalChanges, 0);
    });

    test('toString with changes', () {
      const summary = PkSyncSummary(membersPulled: 2, membersPushed: 1);
      expect(summary.toString(), contains('2 pulled'));
      expect(summary.toString(), contains('1 pushed'));
    });

    test('toString with no changes', () {
      const summary = PkSyncSummary();
      expect(summary.toString(), 'No changes');
    });
  });
}
