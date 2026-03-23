import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // TimelineState
  // ══════════════════════════════════════════════════════════════════════════

  group('TimelineState', () {
    test('default pixelsPerHour is 60', () {
      const state = TimelineState();
      expect(state.pixelsPerHour, 60.0);
    });

    test('copyWith preserves unchanged fields', () {
      const state = TimelineState(pixelsPerHour: 80.0);
      final updated = state.copyWith(pixelsPerHour: 100.0);
      expect(updated.pixelsPerHour, 100.0);
    });

    test('copyWith with no args preserves all fields', () {
      const state = TimelineState(pixelsPerHour: 75.0);
      final updated = state.copyWith();
      expect(updated.pixelsPerHour, state.pixelsPerHour);
    });

    test('min and max zoom bounds are defined', () {
      expect(TimelineState.minPixelsPerHour, 20.0);
      expect(TimelineState.maxPixelsPerHour, 200.0);
      expect(
        TimelineState.minPixelsPerHour,
        lessThan(TimelineState.maxPixelsPerHour),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // TimelineMemberRow
  // ══════════════════════════════════════════════════════════════════════════

  group('TimelineMemberRow', () {
    test('holds member and sessions', () {
      final member = Member(
        id: 'm-1',
        name: 'Alice',
        createdAt: DateTime(2026, 1, 1),
      );
      final sessions = [
        FrontingSession(
          id: 's-1',
          startTime: DateTime(2026, 3, 20, 10, 0),
          endTime: DateTime(2026, 3, 20, 12, 0),
          memberId: 'm-1',
        ),
        FrontingSession(
          id: 's-2',
          startTime: DateTime(2026, 3, 20, 14, 0),
          memberId: 'm-1',
        ),
      ];

      final row = TimelineMemberRow(member: member, sessions: sessions);
      expect(row.member.id, 'm-1');
      expect(row.sessions.length, 2);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Co-fronter expansion logic (extracted from timelineRowsProvider)
  // ══════════════════════════════════════════════════════════════════════════

  group('Co-fronter expansion logic', () {
    // Replicate the grouping logic from timelineRowsProvider to test it
    // without requiring a full Riverpod container.
    Map<String, List<FrontingSession>> groupSessionsByMember(
      List<FrontingSession> sessions,
    ) {
      final rowMap = <String, List<FrontingSession>>{};
      for (final session in sessions) {
        final primaryId = session.memberId;
        if (primaryId != null) {
          rowMap.putIfAbsent(primaryId, () => []).add(session);
        }
        for (final coId in session.coFronterIds) {
          rowMap.putIfAbsent(coId, () => []).add(session);
        }
      }
      return rowMap;
    }

    test('primary fronter gets their session', () {
      final sessions = [
        FrontingSession(
          id: 's-1',
          startTime: DateTime(2026, 3, 20, 10, 0),
          memberId: 'alice',
        ),
      ];

      final grouped = groupSessionsByMember(sessions);
      expect(grouped['alice'], hasLength(1));
      expect(grouped['alice']!.first.id, 's-1');
    });

    test('co-fronters each get their own entry', () {
      final sessions = [
        FrontingSession(
          id: 's-1',
          startTime: DateTime(2026, 3, 20, 10, 0),
          memberId: 'alice',
          coFronterIds: ['bob', 'charlie'],
        ),
      ];

      final grouped = groupSessionsByMember(sessions);
      expect(grouped['alice'], hasLength(1));
      expect(grouped['bob'], hasLength(1));
      expect(grouped['charlie'], hasLength(1));
      // All three reference the same session
      expect(grouped['alice']!.first.id, 's-1');
      expect(grouped['bob']!.first.id, 's-1');
      expect(grouped['charlie']!.first.id, 's-1');
    });

    test('member with multiple sessions gets all of them', () {
      final sessions = [
        FrontingSession(
          id: 's-1',
          startTime: DateTime(2026, 3, 20, 10, 0),
          endTime: DateTime(2026, 3, 20, 12, 0),
          memberId: 'alice',
        ),
        FrontingSession(
          id: 's-2',
          startTime: DateTime(2026, 3, 20, 14, 0),
          memberId: 'alice',
        ),
      ];

      final grouped = groupSessionsByMember(sessions);
      expect(grouped['alice'], hasLength(2));
    });

    test('co-fronter appears in both their co-fronted session and own session', () {
      final sessions = [
        FrontingSession(
          id: 's-1',
          startTime: DateTime(2026, 3, 20, 10, 0),
          memberId: 'alice',
          coFronterIds: ['bob'],
        ),
        FrontingSession(
          id: 's-2',
          startTime: DateTime(2026, 3, 20, 14, 0),
          memberId: 'bob',
        ),
      ];

      final grouped = groupSessionsByMember(sessions);
      expect(grouped['alice'], hasLength(1));
      expect(grouped['bob'], hasLength(2)); // co-fronted + own session
    });

    test('session with null memberId only adds co-fronters', () {
      final sessions = [
        FrontingSession(
          id: 's-1',
          startTime: DateTime(2026, 3, 20, 10, 0),
          memberId: null,
          coFronterIds: ['bob'],
        ),
      ];

      final grouped = groupSessionsByMember(sessions);
      expect(grouped.containsKey(null), isFalse);
      expect(grouped['bob'], hasLength(1));
    });

    test('empty sessions list produces empty map', () {
      final grouped = groupSessionsByMember([]);
      expect(grouped, isEmpty);
    });

    test('session with no co-fronters only appears for primary', () {
      final sessions = [
        FrontingSession(
          id: 's-1',
          startTime: DateTime(2026, 3, 20, 10, 0),
          memberId: 'alice',
          coFronterIds: [],
        ),
      ];

      final grouped = groupSessionsByMember(sessions);
      expect(grouped.keys, ['alice']);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // TimelineMemberRow.resolveColor
  // ══════════════════════════════════════════════════════════════════════════

  group('TimelineMemberRow.resolveColor', () {
    const accent = AppColors.prismPurple;

    test('uses custom color when enabled and hex is set', () {
      final member = Member(
        id: 'm-1',
        name: 'Alice',
        createdAt: DateTime(2026, 1, 1),
        customColorEnabled: true,
        customColorHex: '#FF0000',
      );
      final row = TimelineMemberRow(member: member, sessions: const []);
      final color = row.resolveColor(0, accent, Brightness.dark);
      expect(color, AppColors.fromHex('#FF0000'));
    });

    test('falls back to generated color when custom color disabled', () {
      final member = Member(
        id: 'm-1',
        name: 'Bob',
        createdAt: DateTime(2026, 1, 1),
        customColorEnabled: false,
      );
      final row = TimelineMemberRow(member: member, sessions: const []);
      final color = row.resolveColor(0, accent, Brightness.dark);
      expect(color, AppColors.generatedColor(0, accent, Brightness.dark));
    });

    test('falls back to generated color when hex is null', () {
      final member = Member(
        id: 'm-1',
        name: 'Charlie',
        createdAt: DateTime(2026, 1, 1),
        customColorEnabled: true,
        customColorHex: null,
      );
      final row = TimelineMemberRow(member: member, sessions: const []);
      final color = row.resolveColor(2, accent, Brightness.light);
      expect(color, AppColors.generatedColor(2, accent, Brightness.light));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // AppColors.generatedColor
  // ══════════════════════════════════════════════════════════════════════════

  group('AppColors.generatedColor', () {
    const accent = AppColors.prismPurple;

    test('different indices produce different colors', () {
      final c0 = AppColors.generatedColor(0, accent, Brightness.dark);
      final c1 = AppColors.generatedColor(1, accent, Brightness.dark);
      final c2 = AppColors.generatedColor(2, accent, Brightness.dark);
      expect(c0, isNot(equals(c1)));
      expect(c1, isNot(equals(c2)));
      expect(c0, isNot(equals(c2)));
    });

    test('same index is deterministic', () {
      final a = AppColors.generatedColor(3, accent, Brightness.dark);
      final b = AppColors.generatedColor(3, accent, Brightness.dark);
      expect(a, equals(b));
    });

    test('light and dark brightness produce different colors', () {
      final light = AppColors.generatedColor(0, accent, Brightness.light);
      final dark = AppColors.generatedColor(0, accent, Brightness.dark);
      expect(light, isNot(equals(dark)));
    });

    test('first color hue is roughly opposite the accent', () {
      final accentHue = HSLColor.fromColor(accent).hue;
      final generated = AppColors.generatedColor(0, accent, Brightness.dark);
      final generatedHue = HSLColor.fromColor(generated).hue;
      // Should be ~180° from accent (with golden angle offset: 180 + 0*137.5 = 180)
      final hueDiff = (generatedHue - accentHue).abs();
      final wrappedDiff = hueDiff > 180 ? 360 - hueDiff : hueDiff;
      expect(wrappedDiff, closeTo(180, 5));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Zoom clamping logic
  // ══════════════════════════════════════════════════════════════════════════

  group('Zoom clamping', () {
    // Replicate the zoom logic from TimelineStateNotifier
    double zoomIn(double current) {
      return (current * 1.5).clamp(
        TimelineState.minPixelsPerHour,
        TimelineState.maxPixelsPerHour,
      );
    }

    double zoomOut(double current) {
      return (current / 1.5).clamp(
        TimelineState.minPixelsPerHour,
        TimelineState.maxPixelsPerHour,
      );
    }

    test('zoom in increases pixelsPerHour', () {
      expect(zoomIn(60.0), 90.0);
    });

    test('zoom out decreases pixelsPerHour', () {
      expect(zoomOut(60.0), 40.0);
    });

    test('zoom in clamps at max', () {
      expect(zoomIn(180.0), TimelineState.maxPixelsPerHour);
      expect(zoomIn(200.0), TimelineState.maxPixelsPerHour);
    });

    test('zoom out clamps at min', () {
      expect(zoomOut(25.0), TimelineState.minPixelsPerHour);
      expect(zoomOut(20.0), TimelineState.minPixelsPerHour);
    });

    test('repeated zoom in eventually hits max', () {
      double value = 60.0;
      for (int i = 0; i < 20; i++) {
        value = zoomIn(value);
      }
      expect(value, TimelineState.maxPixelsPerHour);
    });

    test('repeated zoom out eventually hits min', () {
      double value = 60.0;
      for (int i = 0; i < 20; i++) {
        value = zoomOut(value);
      }
      expect(value, TimelineState.minPixelsPerHour);
    });
  });
}
