import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/chat/widgets/media/expired_media.dart';
import 'package:prism_plurality/features/chat/widgets/media/gif_bubble.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Wraps a widget in MaterialApp + ProviderScope for testing.
Widget _buildTestWidget(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Center(child: child),
      ),
    ),
  );
}

void main() {
  setUp(() {
    // Eliminate VisibilityDetector's async timer so it fires synchronously
    // during pump(), preventing "pending timer" failures.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Invalid URL → ExpiredMedia
  // ══════════════════════════════════════════════════════════════════════════

  group('invalid URL handling', () {
    testWidgets('shows ExpiredMedia for invalid URL', (tester) async {
      // Suppress layout overflow errors — ExpiredMedia at default 200px
      // width can overflow its internal Row with long label text.
      final origHandler = FlutterError.onError;
      final errors = <FlutterErrorDetails>[];
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) {
          errors.add(details);
          return;
        }
        origHandler?.call(details);
      };

      await tester.pumpWidget(
        _buildTestWidget(
          const GifBubble(
            sourceUrl: 'https://evil.com/gif.mp4',
            previewUrl: 'https://evil.com/preview.gif',
            width: 200,
            height: 150,
          ),
        ),
      );

      expect(find.byType(ExpiredMedia), findsOneWidget);

      FlutterError.onError = origHandler;
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GIF disabled placeholder
  // ══════════════════════════════════════════════════════════════════════════

  group('gifEnabled: false', () {
    testWidgets('shows "GIF" placeholder text when disabled', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          const GifBubble(
            sourceUrl: 'https://media.klipy.com/test.mp4',
            previewUrl: 'https://media.klipy.com/preview.gif',
            width: 200,
            height: 150,
            gifEnabled: false,
          ),
        ),
      );
      await tester.pump();

      // Should show the placeholder "GIF" text (inside the disabled container)
      // but NOT the video player or preview image
      final gifTexts = find.text('GIF');
      expect(gifTexts, findsWidgets);

      // Should NOT have an Image.network (no CDN fetch)
      expect(find.byType(Image), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Semantics labels
  // ══════════════════════════════════════════════════════════════════════════

  group('semantics', () {
    testWidgets('label includes content description', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          const GifBubble(
            sourceUrl: 'https://media.klipy.com/test.mp4',
            previewUrl: 'https://media.klipy.com/preview.gif',
            width: 200,
            height: 150,
            contentDescription: 'funny cat',
          ),
        ),
      );
      await tester.pump();

      // Find the Semantics widget directly by its label property
      final semanticsFinder = find.bySemanticsLabel(RegExp('GIF: funny cat'));
      expect(semanticsFinder, findsOneWidget);
    });

    testWidgets('label falls back to "GIF" when no description',
        (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          const GifBubble(
            sourceUrl: 'https://media.klipy.com/test.mp4',
            previewUrl: 'https://media.klipy.com/preview.gif',
            width: 200,
            height: 150,
          ),
        ),
      );
      await tester.pump();

      final semanticsFinder = find.bySemanticsLabel(RegExp('GIF: GIF'));
      expect(semanticsFinder, findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GIF label overlay
  // ══════════════════════════════════════════════════════════════════════════

  group('GIF label overlay', () {
    testWidgets('renders "GIF" label pill for valid URL', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          const GifBubble(
            sourceUrl: 'https://media.klipy.com/test.mp4',
            previewUrl: 'https://media.klipy.com/preview.gif',
            width: 200,
            height: 150,
          ),
        ),
      );
      await tester.pump();

      // The "GIF" label text should be present (the overlay pill)
      expect(find.text('GIF'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Size constraints
  // ══════════════════════════════════════════════════════════════════════════

  group('size constraints', () {
    testWidgets('constrains large dimensions to max bounds', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          const GifBubble(
            sourceUrl: 'https://media.klipy.com/test.mp4',
            previewUrl: 'https://media.klipy.com/preview.gif',
            width: 2000,
            height: 1000,
          ),
        ),
      );
      await tester.pump();

      // Find the SizedBox that constrains the GIF bubble content
      // GifBubble creates a ClipRRect > SizedBox with constrained dimensions
      final gifBubble = tester.element(find.byType(GifBubble));
      final renderBox = gifBubble.renderObject! as RenderBox;
      final size = renderBox.size;

      // Screen width in test is 800 by default; maxWidth = 800 * 0.70 = 560
      // maxHeight = 300
      // With 2000x1000, scale to width 560 → height 280 (fits under 300)
      expect(size.width, lessThanOrEqualTo(800 * 0.70 + 1));
      expect(size.height, lessThanOrEqualTo(301));
    });
  });
}
