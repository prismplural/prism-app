import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/notes/views/notes_list_screen.dart';

void main() {
  final sampleNote = Note(
    id: 'note-1',
    title: 'Test Note',
    body: 'Some body text',
    colorHex: '#FF0000',
    date: DateTime(2026, 3, 21),
    createdAt: DateTime(2026, 3, 21),
    modifiedAt: DateTime(2026, 3, 21),
  );

  final noteNoColor = Note(
    id: 'note-2',
    title: 'Plain Note',
    body: 'No color here',
    date: DateTime(2026, 3, 20),
    createdAt: DateTime(2026, 3, 20),
    modifiedAt: DateTime(2026, 3, 20),
  );

  Widget buildSubject({List<Note> notes = const []}) {
    return ProviderScope(
      overrides: [
        allNotesProvider.overrideWith(
          (ref) => Stream.value(notes),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: NotesListScreen(),
      ),
    );
  }

  group('NotesListScreen', () {
    testWidgets('shows empty state when no notes exist', (tester) async {
      await tester.pumpWidget(buildSubject(notes: []));
      await tester.pumpAndSettle();

      expect(find.text('No notes yet'), findsOneWidget);
      expect(
        find.text('Create notes to keep track of thoughts and observations'),
        findsOneWidget,
      );
    });

    testWidgets('lists notes when data exists', (tester) async {
      await tester.pumpWidget(buildSubject(notes: [sampleNote, noteNoColor]));
      await tester.pumpAndSettle();

      expect(find.text('Test Note'), findsOneWidget);
      expect(find.text('Plain Note'), findsOneWidget);
      expect(find.text('Some body text'), findsOneWidget);
    });

    testWidgets('renders color bar when colorHex is set', (tester) async {
      await tester.pumpWidget(buildSubject(notes: [sampleNote]));
      await tester.pumpAndSettle();

      // The color bar is a ColoredBox with a red color.
      final colored =
          tester.widgetList<ColoredBox>(find.byType(ColoredBox));
      final colorBar = colored.where(
        (c) => c.color == const Color(0xFFFF0000),
      );
      expect(colorBar, isNotEmpty);
    });

    testWidgets('malformed colorHex does not crash', (tester) async {
      final badNote = Note(
        id: 'note-bad',
        title: 'Bad Color Note',
        body: 'This has a bad color',
        colorHex: 'not-a-color',
        date: DateTime(2026, 3, 21),
        createdAt: DateTime(2026, 3, 21),
        modifiedAt: DateTime(2026, 3, 21),
      );

      await tester.pumpWidget(buildSubject(notes: [badNote]));
      await tester.pumpAndSettle();

      // Should render without crashing; the note title is still visible.
      expect(find.text('Bad Color Note'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('add action button is present in top bar', (tester) async {
      await tester.pumpWidget(buildSubject(notes: []));
      await tester.pumpAndSettle();

      expect(find.byIcon(AppIcons.add), findsOneWidget);
    });
  });
}
