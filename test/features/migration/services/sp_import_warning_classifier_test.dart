import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/migration/services/sp_import_warning_classifier.dart';

void main() {
  group('SpImportWarningClassifier.classify', () {
    // Helper: classify a single warning and return the kind.
    SpImportWarningKind kindOf(String warning) {
      final result = SpImportWarningClassifier.classify([warning]);
      expect(result, hasLength(1));
      return result.first.kind;
    }

    // ── Empty input ──────────────────────────────────────────────────────────

    test('returns [] for empty input', () {
      expect(SpImportWarningClassifier.classify([]), isEmpty);
    });

    test('retired Simply Plural media is distinct from avatar failures', () {
      expect(
        kindOf('Retired Simply Plural media skipped: 1 bio image(s)'),
        SpImportWarningKind.retiredMedia,
      );
    });

    // ── avatars ──────────────────────────────────────────────────────────────
    // Sources: sp_importer.dart:1514, 1256, 1235, 1286

    test('per-member avatar download failure → avatars', () {
      expect(
        kindOf('Avatar download failed for abc-uuid-123'),
        SpImportWarningKind.avatars,
      );
    });

    test('aggregate avatar download count → avatars', () {
      expect(
        kindOf('5 avatar(s) failed to download'),
        SpImportWarningKind.avatars,
      );
    });

    test('system avatar download failure → avatars', () {
      expect(
        kindOf('System avatar failed to download'),
        SpImportWarningKind.avatars,
      );
    });

    test(
      'avatar ZIP import error with embedded exception → avatars, not missingReferences',
      () {
        // Verifies that the zip-error path (which may embed an exception string
        // containing "not found") is classified as avatars, not missingReferences.
        // Source: sp_importer.dart:1286 — 'Could not import avatar ZIP: $e'
        expect(
          kindOf(
            'Could not import avatar ZIP: '
            'FormatException: Could not read avatar ZIP: invalid ZIP',
          ),
          SpImportWarningKind.avatars,
        );
      },
    );

    // ── avatars: ZIP-image warnings from sp_avatar_zip_importer.dart ─────────
    // These strings contain "zip image" but no "avatar"; without the extended
    // rule they would fall through to missingReferences via the "skipped" check.

    test('unsupported ZIP image → avatars', () {
      // Source: sp_avatar_zip_importer.dart _normalizedBytes
      expect(
        kindOf('Skipped unsupported ZIP image: photo.tiff'),
        SpImportWarningKind.avatars,
      );
    });

    test('oversized ZIP image → avatars', () {
      // Source: sp_avatar_zip_importer.dart _importArchiveFiles (size check)
      expect(
        kindOf('Skipped oversized ZIP image: photo.png'),
        SpImportWarningKind.avatars,
      );
    });

    test('empty ZIP image → avatars', () {
      // Source: sp_avatar_zip_importer.dart _normalizedBytes
      expect(
        kindOf('Skipped empty ZIP image: photo.jpg'),
        SpImportWarningKind.avatars,
      );
    });

    test('ZIP image for missing member → avatars', () {
      // Source: sp_avatar_zip_importer.dart _importArchiveFiles
      expect(
        kindOf('Skipped ZIP image for missing member: abc-uuid-123'),
        SpImportWarningKind.avatars,
      );
    });

    test('no supported images in ZIP → avatars', () {
      // Source: sp_avatar_zip_importer.dart _importArchiveFiles (imagesFound==0)
      expect(
        kindOf('No supported images were found in the avatar ZIP.'),
        SpImportWarningKind.avatars,
      );
    });

    test('unmatched ZIP images aggregate warning → avatars', () {
      // Source: sp_avatar_zip_importer.dart _importArchiveFiles (unmatchedImages>0)
      expect(
        kindOf(
          'Skipped 3 ZIP image(s) that did not match imported Simply Plural members.',
        ),
        SpImportWarningKind.avatars,
      );
    });

    // ── encryptedMessages ────────────────────────────────────────────────────
    // Source: sp_mapper.dart:1005-1011

    test('encrypted chat messages → encryptedMessages', () {
      // Actual emit-site string (sp_mapper.dart:1006-1011); plan fixture
      // had shorter phrasing — using the real string here.
      expect(
        kindOf(
          'Skipped 9 Simply Plural chat message(s) that appear to still be '
          'encrypted in the export. Request a fresh Simply Plural export or '
          'import through the API to include readable chat content.',
        ),
        SpImportWarningKind.encryptedMessages,
      );
    });

    // ── dataQuality ──────────────────────────────────────────────────────────
    // Source: sp_mapper.dart:639-643

    test('missing startTime drops → dataQuality', () {
      expect(
        kindOf(
          'Skipped 14 front history entries with no startTime '
          '— the SP export was missing this field for these rows.',
        ),
        SpImportWarningKind.dataQuality,
      );
    });

    // ── syncEmission ─────────────────────────────────────────────────────────
    // Source: sp_importer.dart:1204-1209, 1211-1217

    test('partial sync emission failures → syncEmission', () {
      expect(
        kindOf(
          '3 of 10 sync emissions failed after import. Local data is correct, '
          'but peers may be missing these entries until you edit them or re-run sync.',
        ),
        SpImportWarningKind.syncEmission,
      );
    });

    test('all sync emissions skipped (no emitter) → syncEmission', () {
      expect(
        kindOf(
          '10 sync emissions could not be replayed because the member '
          'repository is not sync-enabled. Local data is correct, but peers '
          'may be missing imported entries until you edit them or re-run sync.',
        ),
        SpImportWarningKind.syncEmission,
      );
    });

    // ── customFrontAdjustments ───────────────────────────────────────────────
    // Sources: sp_mapper.dart:795-843, sp_mapper.dart:1454-1465

    test('CF dropped front-history sessions → customFrontAdjustments', () {
      expect(
        kindOf(
          '3 front-history entries dropped (primary was a skipped custom front).',
        ),
        SpImportWarningKind.customFrontAdjustments,
      );
    });

    test('CF dropped comments → customFrontAdjustments', () {
      expect(
        kindOf(
          '7 comments dropped (attached to skipped custom-front sessions).',
        ),
        SpImportWarningKind.customFrontAdjustments,
      );
    });

    test('open-ended sleep entries clamped → customFrontAdjustments', () {
      expect(
        kindOf('2 open-ended SP sleep entries clamped to 24h duration.'),
        SpImportWarningKind.customFrontAdjustments,
      );
    });

    test(
      'duplicate-start sleep entries collapsed → customFrontAdjustments',
      () {
        expect(
          kindOf('4 duplicate-start SP sleep entries collapsed.'),
          SpImportWarningKind.customFrontAdjustments,
        );
      },
    );

    test(
      'CF synthetic fallbacks (handled as notes) → customFrontAdjustments',
      () {
        expect(
          kindOf(
            '1 front-history references pointed to custom fronts deleted in SP '
            '— handled as notes.',
          ),
          SpImportWarningKind.customFrontAdjustments,
        );
      },
    );

    test('sleep sessions overlap → customFrontAdjustments', () {
      // Actual emit-site (sp_mapper.dart:831-835) differs from plan fixture;
      // real string says "in your timeline" not "in the same batch".
      expect(
        kindOf(
          '3 sleep sessions overlap with other sessions in your timeline '
          '— resolve in the Fronting tab.',
        ),
        SpImportWarningKind.customFrontAdjustments,
      );
    });

    test('stale member mappings scrubbed → customFrontAdjustments', () {
      // Actual emit-site (sp_mapper.dart:837-843) differs from plan fixture.
      expect(
        kindOf(
          '2 previously-imported custom fronts are no longer imported as '
          'members; existing member records remain — delete manually if you '
          'want them gone.',
        ),
        SpImportWarningKind.customFrontAdjustments,
      );
    });

    test('timers firing only when Prism running → customFrontAdjustments', () {
      // Actual emit-site (sp_mapper.dart:1455-1458) differs from plan fixture
      // which used "12 imported timers resolved to existing members."
      expect(
        kindOf(
          '12 imported timers will fire only when Prism is running and sees '
          'the switch.',
        ),
        SpImportWarningKind.customFrontAdjustments,
      );
    });

    test('timers with unresolvable target → customFrontAdjustments', () {
      // Actual emit-site (sp_mapper.dart:1460-1465) differs from plan fixture
      // which used "3 imported timers dropped because target members didn't exist."
      expect(
        kindOf(
          '3 imported timers had a target that could not be resolved and will '
          'fire on any front change.',
        ),
        SpImportWarningKind.customFrontAdjustments,
      );
    });

    // ── missingReferences ────────────────────────────────────────────────────
    // Sources: sp_mapper.dart:492-496, 1030-1033, 1076-1079, 1239-1242,
    //          1292-1295, 1301-1303

    test('front entry primary not found → missingReferences', () {
      expect(
        kindOf(
          'Front entry abc-id: member "xyz-id" not found, '
          'session will have no primary fronter.',
        ),
        SpImportWarningKind.missingReferences,
      );
    });

    test('note member not found → missingReferences', () {
      // Actual emit-site (sp_mapper.dart:1031-1033) ends with
      // "note will not be linked to a member." — plan had "importing without member."
      expect(
        kindOf(
          'Note "Title": member "abc" not found, '
          'note will not be linked to a member.',
        ),
        SpImportWarningKind.missingReferences,
      );
    });

    test('comment front session not found → missingReferences', () {
      expect(
        kindOf('Comment xyz: front session "def" not found, comment skipped.'),
        SpImportWarningKind.missingReferences,
      );
    });

    test('group member not found → missingReferences', () {
      // Actual emit-site (sp_mapper.dart:1240-1241) says "membership skipped."
      // — plan had "skipping group membership." Both contain "not found".
      expect(
        kindOf('Group "Family": member "abc" not found, membership skipped.'),
        SpImportWarningKind.missingReferences,
      );
    });

    test('board message null writtenFor → missingReferences', () {
      // Actual emit-site (sp_mapper.dart:1292-1295) ends with
      // "cannot determine recipient, message skipped."
      expect(
        kindOf(
          'Board message xyz: writtenFor is null — '
          'cannot determine recipient, message skipped.',
        ),
        SpImportWarningKind.missingReferences,
      );
    });

    test('board message writtenFor not found → missingReferences', () {
      // Actual emit-site (sp_mapper.dart:1301-1303) says
      // "not found in member map, message skipped." — plan had "not found in mapped members."
      expect(
        kindOf(
          'Board message xyz: writtenFor "abc" not found in member map, '
          'message skipped.',
        ),
        SpImportWarningKind.missingReferences,
      );
    });

    // ── other ────────────────────────────────────────────────────────────────

    test('unrecognized warning text → other', () {
      expect(
        kindOf("Some new warning we don't recognize"),
        SpImportWarningKind.other,
      );
    });

    // ── ordering: first-match wins ───────────────────────────────────────────

    test(
      'warning matching both avatars and missingReferences → avatars (rule 1 beats rule 6)',
      () {
        // "avatar download" matches rule 1; "not found" also present but rule 1
        // fires first.
        final result = SpImportWarningClassifier.classify([
          'Avatar download failed for some-id: not found on CDN',
        ]);
        expect(result, hasLength(1));
        expect(result.first.kind, SpImportWarningKind.avatars);
      },
    );

    // ── multi-warning input ───────────────────────────────────────────────────

    test(
      'multiple warnings from different categories produce multiple categories',
      () {
        final result = SpImportWarningClassifier.classify([
          'Avatar download failed for abc',
          'Front entry x: member "y" not found, session will have no primary fronter.',
          "Some new warning we don't recognize",
        ]);
        final kinds = result.map((c) => c.kind).toSet();
        expect(
          kinds,
          containsAll([
            SpImportWarningKind.avatars,
            SpImportWarningKind.missingReferences,
            SpImportWarningKind.other,
          ]),
        );
      },
    );

    test('result order matches SpImportWarningKind declaration order', () {
      // avatars (0), missingReferences (1), other (6) — should appear in that
      // order regardless of input order.
      final result = SpImportWarningClassifier.classify([
        "Some new warning we don't recognize", // other
        'Avatar download failed for abc', // avatars
        'Front entry x: member "y" not found, session will have no primary fronter.', // missingReferences
      ]);
      expect(result.map((c) => c.kind).toList(), [
        SpImportWarningKind.avatars,
        SpImportWarningKind.missingReferences,
        SpImportWarningKind.other,
      ]);
    });

    // ── severity ─────────────────────────────────────────────────────────────

    test('syncEmission has error severity', () {
      final result = SpImportWarningClassifier.classify([
        '1 sync emissions could not be replayed because the member repository '
            'is not sync-enabled. Local data is correct.',
      ]);
      expect(result.first.severity, SpImportWarningSeverity.error);
    });

    test('customFrontAdjustments has info severity', () {
      final result = SpImportWarningClassifier.classify([
        '1 open-ended SP sleep entries clamped to 24h duration.',
      ]);
      expect(result.first.severity, SpImportWarningSeverity.info);
    });
  });
}
