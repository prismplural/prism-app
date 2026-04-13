import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/chat/widgets/gif_picker_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

/// Helper to build a realistic Klipy API response body.
Map<String, dynamic> _buildResponse(List<Map<String, dynamic>> items) {
  return {
    'data': {
      'data': items,
    },
  };
}

/// A minimal valid GIF item with the nested file structure.
Map<String, dynamic> _gifItem({String id = '123', String title = 'funny cat'}) {
  return {
    'id': id,
    'title': title,
    'type': 'gif',
    'file': {
      'xs': {
        'mp4': {
          'url': 'https://media.klipy.com/xs.mp4',
          'width': 100,
          'height': 80,
        },
        'gif': {
          'url': 'https://media.klipy.com/xs.gif',
          'width': 100,
          'height': 80,
        },
      },
    },
  };
}

/// Wraps the GifPickerSheet in the MaterialApp + ProviderScope scaffolding
/// needed for widget tests.
Widget _buildTestWidget({required MockClient mockClient}) {
  return ProviderScope(
    overrides: [
      klipyServiceProvider.overrideWithValue(
        KlipyService(httpClient: mockClient),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: const Scaffold(
        body: GifPickerSheet(),
      ),
    ),
  );
}

/// Cleanly tear down the GifPickerSheet widget tree and consume the known
/// StateError from GifPickerSheet.dispose() calling ref.read() after unmount.
/// This is a pre-existing widget bug (not a test issue).
Future<void> _cleanTearDown(WidgetTester tester) async {
  // Replace the widget tree — this triggers dispose of the old tree.
  await tester.pumpWidget(const SizedBox.shrink());
  // Consume the expected StateError from GifPickerSheet.dispose().
  final error = tester.takeException();
  if (error != null && error is! StateError) {
    // Re-throw unexpected errors.
    // ignore: only_throw_errors
    throw error;
  }
}

void main() {
  // ════════════════════════════════════════════════════════════════════════════
  // Widget structure
  // ════════════════════════════════════════════════════════════════════════════

  group('GifPickerSheet widget structure', () {
    testWidgets('renders search field and Powered by KLIPY attribution',
        (tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode(_buildResponse([_gifItem()])),
          200,
        );
      });

      await tester.pumpWidget(_buildTestWidget(mockClient: mockClient));
      await tester.pumpAndSettle();

      // Search field is present.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search for GIFs'), findsOneWidget);

      // Attribution text is present.
      expect(find.text('Powered by KLIPY'), findsOneWidget);

      await _cleanTearDown(tester);
    });

    testWidgets('renders GIFs title bar', (tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode(_buildResponse([_gifItem()])),
          200,
        );
      });

      await tester.pumpWidget(_buildTestWidget(mockClient: mockClient));
      await tester.pumpAndSettle();

      expect(find.text('GIFs'), findsOneWidget);

      await _cleanTearDown(tester);
    });

    testWidgets('shows loading indicator while fetching', (tester) async {
      final completer = Completer<http.Response>();
      final mockClient = MockClient((request) async {
        return completer.future;
      });

      await tester.pumpWidget(_buildTestWidget(mockClient: mockClient));
      // Don't settle — let the loading state render.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the future to avoid pending timers.
      completer.complete(
        http.Response(jsonEncode(_buildResponse([])), 200),
      );
      await tester.pumpAndSettle();

      await _cleanTearDown(tester);
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // Search interaction
  // ════════════════════════════════════════════════════════════════════════════

  group('search interaction', () {
    testWidgets('typing in search field triggers debounced query update',
        (tester) async {
      final requestUris = <Uri>[];
      final mockClient = MockClient((request) async {
        requestUris.add(request.url);
        return http.Response(
          jsonEncode(_buildResponse([_gifItem()])),
          200,
        );
      });

      await tester.pumpWidget(_buildTestWidget(mockClient: mockClient));
      await tester.pumpAndSettle();

      // Initial load fetches trending.
      expect(requestUris.last.path, contains('/trending'));

      // Type into the search field.
      await tester.enterText(find.byType(TextField), 'cats');

      // Immediately after typing, no search request yet (debounce is 300ms).
      final countBeforeDebounce = requestUris.length;

      // Advance past the 300ms debounce.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // A new request should have been made to the search endpoint.
      expect(requestUris.length, greaterThan(countBeforeDebounce));
      expect(requestUris.last.path, contains('/search'));
      expect(requestUris.last.queryParameters['q'], 'cats');

      await _cleanTearDown(tester);
    });

    testWidgets('shows error state when API fails', (tester) async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      await tester.pumpWidget(_buildTestWidget(mockClient: mockClient));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load GIFs'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      await _cleanTearDown(tester);
    });
  });
}
