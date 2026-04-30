import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_session_row.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

FrontingSession _session({
  DateTime? startTime,
  DateTime? endTime,
  SleepQuality? quality,
  String? notes,
}) {
  final start = startTime ?? DateTime(2026, 4, 29, 22, 32);
  return FrontingSession(
    id: 'sleep-test-1',
    startTime: start,
    endTime: endTime ?? start.add(const Duration(hours: 8, minutes: 12)),
    sessionType: SessionType.sleep,
    quality: quality,
    notes: notes,
  );
}

Widget _buildSubject({
  required FrontingSession session,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: SleepSessionRow(
        session: session,
        onTap: onTap ?? () {},
        onLongPress: onLongPress ?? () {},
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('SleepSessionRow', () {
    // ── Renders core content ─────────────────────────────────────────────────

    testWidgets('renders date headline with day and month', (tester) async {
      await tester.pumpWidget(
        _buildSubject(session: _session()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Apr'), findsWidgets);
      expect(find.textContaining('29'), findsWidgets);
    });

    testWidgets('renders duration in headline row', (tester) async {
      await tester.pumpWidget(
        _buildSubject(session: _session()),
      );
      await tester.pumpAndSettle();

      // 8h 12m duration
      expect(find.text('8h 12m'), findsOneWidget);
    });

    testWidgets('renders quality icon (bedtime moon icon)', (tester) async {
      await tester.pumpWidget(
        _buildSubject(session: _session(quality: SleepQuality.good)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Good'), findsOneWidget);
    });

    testWidgets('renders time range in subtitle', (tester) async {
      await tester.pumpWidget(
        _buildSubject(session: _session()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('→'), findsOneWidget);
    });

    // ── Notes visibility ─────────────────────────────────────────────────────

    testWidgets('shows notes preview when notes are present', (tester) async {
      const notesText = 'Vivid dreams about flying';
      await tester.pumpWidget(
        _buildSubject(session: _session(notes: notesText)),
      );
      await tester.pumpAndSettle();

      expect(find.text(notesText), findsOneWidget);
    });

    testWidgets('hides notes preview when notes are null', (tester) async {
      await tester.pumpWidget(
        _buildSubject(session: _session()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vivid dreams about flying'), findsNothing);
    });

    testWidgets('hides notes preview when notes are empty string',
        (tester) async {
      await tester.pumpWidget(
        _buildSubject(session: _session(notes: '')),
      );
      await tester.pumpAndSettle();

      final italicTexts = tester.widgetList<Text>(find.byType(Text)).where(
            (t) => t.style?.fontStyle == FontStyle.italic,
          );
      expect(italicTexts, isEmpty);
    });

    // ── SleepQuality.unknown ─────────────────────────────────────────────────

    testWidgets('shows "Not rated" label for SleepQuality.unknown',
        (tester) async {
      await tester.pumpWidget(
        _buildSubject(session: _session(quality: SleepQuality.unknown)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not rated'), findsOneWidget);
    });

    testWidgets('shows "Not rated" label when quality is null', (tester) async {
      await tester.pumpWidget(
        _buildSubject(session: _session()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not rated'), findsOneWidget);
    });

    // ── Future-date warning ──────────────────────────────────────────────────

    testWidgets('shows warning chip for future-dated session', (tester) async {
      final futureStart = DateTime.now().add(const Duration(days: 1));
      await tester.pumpWidget(
        _buildSubject(
          session: _session(
            startTime: futureStart,
            endTime: futureStart.add(const Duration(hours: 7)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Date looks off'), findsOneWidget);
    });

    testWidgets('does not show warning chip for past-dated session',
        (tester) async {
      await tester.pumpWidget(
        _buildSubject(session: _session()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Date looks off'), findsNothing);
    });

    // ── Callbacks ────────────────────────────────────────────────────────────

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildSubject(
          session: _session(),
          onTap: () => tapped = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SleepSessionRow));
      expect(tapped, isTrue);
    });

    testWidgets('calls onLongPress when long-pressed', (tester) async {
      var longPressed = false;
      await tester.pumpWidget(
        _buildSubject(
          session: _session(),
          onLongPress: () => longPressed = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(SleepSessionRow));
      expect(longPressed, isTrue);
    });

    // ── Semantics ────────────────────────────────────────────────────────────

    testWidgets('has button semantics role', (tester) async {
      await tester.pumpWidget(
        _buildSubject(session: _session()),
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(SleepSessionRow));
      expect(semantics.flagsCollection.isButton, isTrue);
    });

    testWidgets('semantic label contains date and duration', (tester) async {
      await tester.pumpWidget(
        _buildSubject(session: _session()),
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(SleepSessionRow));
      expect(semantics.label, contains('Apr'));
      expect(semantics.label, contains('hour'));
    });

    testWidgets('semantic hint contains "Long press"', (tester) async {
      await tester.pumpWidget(
        _buildSubject(session: _session()),
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(SleepSessionRow));
      expect(semantics.hint, contains('Long press'));
    });

    // ── Touch target ─────────────────────────────────────────────────────────

    testWidgets('touch target is at least 48dp tall', (tester) async {
      await tester.pumpWidget(
        _buildSubject(session: _session()),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(SleepSessionRow));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });
}
