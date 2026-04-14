import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/widgets/media/voice_bubble.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

Widget _buildTestWidget({
  int durationMs = 5000,
  bool isPlaying = false,
  double progress = 0.0,
  double speed = 1.0,
  bool isLoading = false,
  VoidCallback? onPlayPause,
  ValueChanged<double>? onSeek,
  VoidCallback? onSpeedTap,
}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Center(
          child: VoiceBubble(
            durationMs: durationMs,
            isPlaying: isPlaying,
            progress: progress,
            speed: speed,
            isLoading: isLoading,
            onPlayPause: onPlayPause,
            onSeek: onSeek,
            onSpeedTap: onSpeedTap,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('VoiceBubble', () {
    // ── Loading state ─────────────────────────────────────────────────────

    group('loading state', () {
      testWidgets('shows PrismSpinner when isLoading is true',
          (tester) async {
        await tester.pumpWidget(_buildTestWidget(isLoading: true));

        expect(find.byType(PrismSpinner), findsOneWidget);
      });

      testWidgets('does not show play/pause IconButton when isLoading is true',
          (tester) async {
        await tester.pumpWidget(_buildTestWidget(isLoading: true));

        expect(find.byType(IconButton), findsNothing);
      });
    });

    // ── Play/pause icon ───────────────────────────────────────────────────

    group('play/pause icon', () {
      testWidgets('shows play arrow icon when not playing', (tester) async {
        await tester.pumpWidget(_buildTestWidget(isPlaying: false));

        expect(find.byIcon(AppIcons.playArrowRounded), findsOneWidget);
        expect(find.byIcon(AppIcons.stopRounded), findsNothing);
      });

      testWidgets('shows stop icon when playing', (tester) async {
        await tester.pumpWidget(_buildTestWidget(isPlaying: true));

        expect(find.byIcon(AppIcons.stopRounded), findsOneWidget);
        expect(find.byIcon(AppIcons.playArrowRounded), findsNothing);
      });
    });

    // ── Duration display ──────────────────────────────────────────────────

    group('duration display', () {
      testWidgets('formats 5000ms as 0:05', (tester) async {
        await tester.pumpWidget(_buildTestWidget(durationMs: 5000));

        expect(find.text('0:05'), findsOneWidget);
      });

      testWidgets('formats 65000ms as 1:05', (tester) async {
        await tester.pumpWidget(_buildTestWidget(durationMs: 65000));

        expect(find.text('1:05'), findsOneWidget);
      });
    });

    // ── Speed chip visibility ─────────────────────────────────────────────

    group('speed chip visibility', () {
      testWidgets('speed chip is visible when onSpeedTap is provided',
          (tester) async {
        await tester.pumpWidget(_buildTestWidget(
          isPlaying: false,
          speed: 1.0,
          onSpeedTap: () {},
        ));

        expect(find.text('1x'), findsOneWidget);
      });

      testWidgets(
          'speed chip is not visible when not playing and onSpeedTap is null',
          (tester) async {
        await tester.pumpWidget(_buildTestWidget(
          isPlaying: false,
          onSpeedTap: null,
        ));

        // The speed text should not appear
        expect(find.text('1x'), findsNothing);
      });

      testWidgets('speed chip is visible when playing even without onSpeedTap',
          (tester) async {
        await tester.pumpWidget(_buildTestWidget(
          isPlaying: true,
          speed: 1.0,
          onSpeedTap: null,
        ));

        expect(find.text('1x'), findsOneWidget);
      });
    });

    // ── Speed chip text ───────────────────────────────────────────────────

    group('speed chip text', () {
      testWidgets('displays 1x for speed 1.0', (tester) async {
        await tester.pumpWidget(_buildTestWidget(
          isPlaying: true,
          speed: 1.0,
        ));

        expect(find.text('1x'), findsOneWidget);
      });

      testWidgets('displays 1.5x for speed 1.5', (tester) async {
        await tester.pumpWidget(_buildTestWidget(
          isPlaying: true,
          speed: 1.5,
        ));

        expect(find.text('1.5x'), findsOneWidget);
      });

      testWidgets('displays 2x for speed 2.0', (tester) async {
        await tester.pumpWidget(_buildTestWidget(
          isPlaying: true,
          speed: 2.0,
        ));

        expect(find.text('2x'), findsOneWidget);
      });
    });

    // ── Accessibility (Semantics) ─────────────────────────────────────────

    group('accessibility', () {
      Finder findSemanticsWithLabel(String label) {
        return find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == label,
        );
      }

      testWidgets('has loading semantics label when loading', (tester) async {
        await tester.pumpWidget(_buildTestWidget(
          isLoading: true,
          durationMs: 5000,
        ));

        expect(
          findSemanticsWithLabel('Loading voice note, 0:05'),
          findsOneWidget,
        );
      });

      testWidgets('has pause semantics label when playing', (tester) async {
        await tester.pumpWidget(_buildTestWidget(
          isPlaying: true,
          durationMs: 5000,
        ));

        expect(
          findSemanticsWithLabel('Pause voice note, 0:05'),
          findsOneWidget,
        );
      });

      testWidgets('has play semantics label when paused', (tester) async {
        await tester.pumpWidget(_buildTestWidget(
          isPlaying: false,
          durationMs: 5000,
        ));

        expect(
          findSemanticsWithLabel('Play voice note, 0:05'),
          findsOneWidget,
        );
      });

      testWidgets('speed chip has correct semantics label', (tester) async {
        await tester.pumpWidget(_buildTestWidget(
          isPlaying: true,
          speed: 1.5,
        ));

        expect(
          findSemanticsWithLabel(
              'Playback speed 1.5x. Double tap to change.'),
          findsOneWidget,
        );
      });
    });
  });
}
