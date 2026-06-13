import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_live_fronters_notice.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';

PkUnmappedFrontersNotice _notice() {
  return PkUnmappedFrontersNotice(
    systemId: 'system-secret',
    switchId: 'switch-secret',
    switchTimestamp: DateTime.utc(2026, 5, 1, 12),
    sortedPkIds: const ['pk-alpha', 'pk-beta'],
    refs: const [
      PkUnmappedFronterRef(
        pkId: 'pk-alpha',
        pkUuid: 'uuid-alpha',
        name: 'Alpha',
        displayName: 'Alpha Display',
        avatarUrl: 'https://cdn.example/alpha.png',
      ),
      PkUnmappedFronterRef(
        pkId: 'pk-beta',
        pkUuid: 'uuid-beta',
        name: 'Beta',
        displayName: 'Beta Display',
        avatarUrl: 'https://cdn.example/beta.png',
      ),
    ],
  );
}

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

  // ── PkSyncMode ───────────────────────────────────────────────────────────

  group('PkSyncMode', () {
    test('JSON round-trip preserves mode', () {
      expect(
        PkSyncMode.fromJson(PkSyncMode.liveFrontsOnly.toJson()),
        PkSyncMode.liveFrontsOnly,
      );
    });

    test('fromJson defaults safely to fullSync for malformed values', () {
      expect(PkSyncMode.fromJson(null), PkSyncMode.fullSync);
      expect(PkSyncMode.fromJson(123), PkSyncMode.fullSync);
      expect(PkSyncMode.fromJson('unknown'), PkSyncMode.fullSync);
    });
  });

  group('PkSleepSyncBehavior', () {
    test('JSON round-trip preserves behavior', () {
      expect(
        PkSleepSyncBehavior.fromJson(
          PkSleepSyncBehavior.leaveUnchanged.toJson(),
        ),
        PkSleepSyncBehavior.leaveUnchanged,
      );
    });

    test('fromJson defaults safely to clearFronters for malformed values', () {
      expect(
        PkSleepSyncBehavior.fromJson(null),
        PkSleepSyncBehavior.clearFronters,
      );
      expect(
        PkSleepSyncBehavior.fromJson(123),
        PkSleepSyncBehavior.clearFronters,
      );
      expect(
        PkSleepSyncBehavior.fromJson('unknown'),
        PkSleepSyncBehavior.clearFronters,
      );
    });
  });

  // ── PkDeleteRiskPreview ─────────────────────────────────────────────────

  group('PkDeleteRiskPreview', () {
    test('totals removals and skipped rows', () {
      const preview = PkDeleteRiskPreview(
        membersToDelete: 1,
        switchesToDelete: 2,
        groupMembershipsToRemove: 3,
        memberProxyTagsToRemove: 4,
        membersSkipped: 4,
        switchesSkipped: 5,
        groupMembershipsSkipped: 6,
      );

      expect(preview.totalToRemove, 10);
      expect(preview.totalSkipped, 15);
      expect(preview.hasRemovals, isTrue);
    });

    test('isSignificant treats any member delete as significant', () {
      expect(
        const PkDeleteRiskPreview(membersToDelete: 1).isSignificant,
        isTrue,
      );
    });

    test('isSignificant treats any proxy tag removal as significant', () {
      expect(
        const PkDeleteRiskPreview(memberProxyTagsToRemove: 1).isSignificant,
        isTrue,
      );
    });

    test('isSignificant treats any switch deletion as significant', () {
      // Binding maintainer decision (2026-06-11): the >= 10 threshold is
      // dropped — a single full switch DELETE against the user's real
      // PluralKit account must be confirmed.
      expect(
        const PkDeleteRiskPreview(switchesToDelete: 1).isSignificant,
        isTrue,
      );
      expect(
        const PkDeleteRiskPreview(switchesToDelete: 9).isSignificant,
        isTrue,
      );
    });

    test(
      'isSignificant treats any group-membership removal as significant',
      () {
        expect(
          const PkDeleteRiskPreview(groupMembershipsToRemove: 1).isSignificant,
          isTrue,
        );
        expect(
          const PkDeleteRiskPreview(groupMembershipsToRemove: 9).isSignificant,
          isTrue,
        );
      },
    );

    test('isSignificant is false only when nothing is removed', () {
      expect(const PkDeleteRiskPreview().isSignificant, isFalse);
      expect(
        const PkDeleteRiskPreview(
          membersSkipped: 5,
          switchesSkipped: 5,
          groupMembershipsSkipped: 5,
        ).isSignificant,
        isFalse,
      );
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

    test('proxyTags default follows bidirectional sync direction', () {
      const config = PkFieldSyncConfig();
      expect(config.proxyTags, PkSyncDirection.bidirectional);
    });

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

    test('reserved keys are ignored', () {
      final json = jsonEncode({
        '__mode__': 'liveFrontsOnly',
        '__futureMetadata__': {'unexpected': true},
        '__global__': {'name': 'pushOnly'},
        'member-1': {'name': 'pullOnly'},
      });

      final result = parseFieldSyncConfig(json);

      expect(result.keys, ['member-1']);
      expect(result['member-1']!.name, PkSyncDirection.pullOnly);
    });

    test('malformed reserved values do not break member parsing', () {
      final json = jsonEncode({
        '__mode__': {'not': 'a string'},
        '__global__': 'not a field config',
        'member-1': {'name': 'pushOnly'},
      });

      final result = parseFieldSyncConfig(json);

      expect(result.keys, ['member-1']);
      expect(result['member-1']!.name, PkSyncDirection.pushOnly);
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

    test('with mode preserves existing global direction', () {
      final withDirection = serializeFieldSyncConfig({
        'member-1': const PkFieldSyncConfig(name: PkSyncDirection.pullOnly),
      }, globalDirection: PkSyncDirection.pushOnly);

      final withMode = serializeFieldSyncConfigWithMode(
        withDirection,
        PkSyncMode.liveFrontsOnly,
      );

      expect(parsePkSyncMode(withMode), PkSyncMode.liveFrontsOnly);
      expect(parseGlobalSyncDirection(withMode), PkSyncDirection.pushOnly);
      expect(
        parseFieldSyncConfig(withMode)['member-1']!.name,
        PkSyncDirection.pullOnly,
      );
    });

    test('with global direction preserves existing mode', () {
      final withMode = serializeFieldSyncConfig({
        'member-1': const PkFieldSyncConfig(name: PkSyncDirection.pullOnly),
      }, mode: PkSyncMode.liveFrontsOnly);

      final withDirection = serializeFieldSyncConfigWithGlobalDirection(
        withMode,
        PkSyncDirection.bidirectional,
      );

      expect(parsePkSyncMode(withDirection), PkSyncMode.liveFrontsOnly);
      expect(
        parseGlobalSyncDirection(withDirection),
        PkSyncDirection.bidirectional,
      );
      expect(
        parseFieldSyncConfig(withDirection)['member-1']!.name,
        PkSyncDirection.pullOnly,
      );
    });

    test('with sleep sync behavior preserves member config and metadata', () {
      final withDirectionAndMode = serializeFieldSyncConfig(
        {'member-1': const PkFieldSyncConfig(name: PkSyncDirection.pullOnly)},
        globalDirection: PkSyncDirection.pushOnly,
        mode: PkSyncMode.liveFrontsOnly,
      );

      final withSleepBehavior = serializeFieldSyncConfigWithSleepSyncBehavior(
        withDirectionAndMode,
        PkSleepSyncBehavior.leaveUnchanged,
      );

      expect(
        parsePkSleepSyncBehavior(withSleepBehavior),
        PkSleepSyncBehavior.leaveUnchanged,
      );
      expect(parsePkSyncMode(withSleepBehavior), PkSyncMode.liveFrontsOnly);
      expect(
        parseGlobalSyncDirection(withSleepBehavior),
        PkSyncDirection.pushOnly,
      );
      expect(
        parseFieldSyncConfig(withSleepBehavior)['member-1']!.name,
        PkSyncDirection.pullOnly,
      );
    });
  });

  // ── metadata helpers ─────────────────────────────────────────────────────

  group('metadata helpers', () {
    test('parsePkSyncMode defaults to fullSync', () {
      expect(parsePkSyncMode(null), PkSyncMode.fullSync);
      expect(parsePkSyncMode(''), PkSyncMode.fullSync);
      expect(parsePkSyncMode('not json'), PkSyncMode.fullSync);
      expect(
        parsePkSyncMode(jsonEncode({'__mode__': 42})),
        PkSyncMode.fullSync,
      );
      expect(
        parsePkSyncMode(jsonEncode({'__mode__': 'unknown'})),
        PkSyncMode.fullSync,
      );
    });

    test('parsePkSyncMode reads liveFrontsOnly', () {
      expect(
        parsePkSyncMode(jsonEncode({'__mode__': 'liveFrontsOnly'})),
        PkSyncMode.liveFrontsOnly,
      );
    });

    test('parsePkSleepSyncBehavior defaults to clearFronters', () {
      expect(parsePkSleepSyncBehavior(null), PkSleepSyncBehavior.clearFronters);
      expect(parsePkSleepSyncBehavior(''), PkSleepSyncBehavior.clearFronters);
      expect(
        parsePkSleepSyncBehavior('not json'),
        PkSleepSyncBehavior.clearFronters,
      );
      expect(
        parsePkSleepSyncBehavior(jsonEncode({'__sleep_sync_behavior__': 42})),
        PkSleepSyncBehavior.clearFronters,
      );
      expect(
        parsePkSleepSyncBehavior(
          jsonEncode({'__sleep_sync_behavior__': 'unknown'}),
        ),
        PkSleepSyncBehavior.clearFronters,
      );
    });

    test('parsePkSleepSyncBehavior reads leaveUnchanged', () {
      expect(
        parsePkSleepSyncBehavior(
          jsonEncode({'__sleep_sync_behavior__': 'leaveUnchanged'}),
        ),
        PkSleepSyncBehavior.leaveUnchanged,
      );
    });

    test('parseGlobalSyncDirection reads __global__ direction', () {
      final json = jsonEncode({
        '__global__': {'name': 'pushOnly'},
      });

      expect(parseGlobalSyncDirection(json), PkSyncDirection.pushOnly);
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

    test('live unmapped fronters are summary details without sync changes', () {
      final summary = PkSyncSummary(liveUnmappedFronters: _notice());

      expect(summary.totalChanges, 0);
      expect(summary.liveUnmappedFrontersCount, 2);
      expect(summary.hasLiveUnmappedFronters, isTrue);
      expect(summary.hasSummaryDetails, isTrue);
      expect(summary.toString(), '2 unmapped current fronters');
    });

    test('stale link messages are summary details without sync changes', () {
      const summary = PkSyncSummary(
        staleLinkMessages: ['A PluralKit switch target was removed.'],
      );

      expect(summary.totalChanges, 0);
      expect(summary.hasSummaryDetails, isTrue);
      expect(summary.toString(), '1 stale links cleared');
    });

    test('JSON stores only safe live unmapped fronter metadata', () {
      final notice = _notice();
      final summary = PkSyncSummary(
        liveUnmappedFronters: notice,
        observedLiveFronters: true,
        observedLiveFrontersDismissalKey: notice.dismissalKey,
      );

      final json = summary.toJson();
      final encoded = jsonEncode(json);

      expect(json.containsKey('liveUnmappedFronters'), isFalse);
      expect(json['liveUnmappedFrontersCount'], 2);
      expect(json['liveUnmappedFrontersDismissalKey'], notice.dismissalKey);
      expect(encoded, isNot(contains('switch-secret')));
      expect(encoded, isNot(contains('pk-alpha')));
      expect(encoded, isNot(contains('uuid-alpha')));
      expect(encoded, isNot(contains('Alpha Display')));
      expect(encoded, isNot(contains('https://cdn.example/alpha.png')));

      final restored = PkSyncSummary.fromJson(json);
      expect(restored.liveUnmappedFronters, isNull);
      expect(restored.liveUnmappedFrontersCount, 2);
      expect(restored.liveUnmappedFrontersDismissalKey, notice.dismissalKey);
      expect(restored.hasSummaryDetails, isTrue);
    });

    test('fromJson ignores legacy raw live unmapped fronter payloads', () {
      final restored = PkSyncSummary.fromJson({
        'liveUnmappedFronters': _notice().toJson(),
      });

      expect(restored.liveUnmappedFronters, isNull);
      expect(restored.liveUnmappedFrontersCount, 0);
      expect(restored.hasLiveUnmappedFronters, isFalse);
    });
  });
}
