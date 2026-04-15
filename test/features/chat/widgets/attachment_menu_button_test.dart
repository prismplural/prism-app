import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/chat/widgets/message_input.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';

Widget _buildTestApp(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('opens attachment actions in a blur popup', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        AttachmentMenuButton(
          gifEnabled: true,
          size: 48,
          onCamera: () {},
          onPhotoLibrary: () {},
          onGif: () {},
        ),
      ),
    );

    expect(find.byType(BlurPopupAnchor), findsOneWidget);
    expect(find.text('Camera'), findsNothing);

    await tester.tap(find.byType(AttachmentMenuButton));
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Photo Library'), findsOneWidget);
    expect(find.text('GIFs'), findsOneWidget);
  });

  testWidgets('omits GIF action when disabled', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        AttachmentMenuButton(
          gifEnabled: false,
          size: 48,
          onCamera: () {},
          onPhotoLibrary: () {},
          onGif: () {},
        ),
      ),
    );

    await tester.tap(find.byType(AttachmentMenuButton));
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Photo Library'), findsOneWidget);
    expect(find.text('GIFs'), findsNothing);
  });

  testWidgets('runs selected action and closes the popup', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      _buildTestApp(
        AttachmentMenuButton(
          gifEnabled: true,
          size: 48,
          onCamera: () => tapped = true,
          onPhotoLibrary: () {},
          onGif: () {},
        ),
      ),
    );

    await tester.tap(find.byType(AttachmentMenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
    expect(find.text('Camera'), findsNothing);
    expect(find.text('Photo Library'), findsNothing);
  });
}
