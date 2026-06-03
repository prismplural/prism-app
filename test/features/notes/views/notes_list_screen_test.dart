import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/notes_repository.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/widgets/note_editor.dart';
import 'package:prism_plurality/features/members/widgets/note_sheet.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
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

  Widget buildSubject({
    List<Note> notes = const [],
    _FakeNotesRepository? notesRepository,
  }) {
    final repository = notesRepository ?? _FakeNotesRepository(notes);
    return ProviderScope(
      overrides: [
        notesRepositoryProvider.overrideWithValue(repository),
        allNotesProvider.overrideWith((ref) => Stream.value(notes)),
        currentFronterProvider.overrideWithValue(const AsyncValue.data(null)),
        systemSettingsProvider.overrideWithValue(
          const AsyncValue.data(SystemSettings()),
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

    testWidgets('wide detail pane prompts for selection when notes exist', (
      tester,
    ) async {
      _setWideWindow(tester);

      await tester.pumpWidget(buildSubject(notes: [sampleNote]));
      await tester.pumpAndSettle();

      expect(find.text('Select a note'), findsOneWidget);
      expect(find.text('No notes yet'), findsNothing);
    });

    testWidgets('wide detail pane keeps empty copy when no notes exist', (
      tester,
    ) async {
      _setWideWindow(tester);

      await tester.pumpWidget(buildSubject(notes: const []));
      await tester.pumpAndSettle();

      expect(find.text('No notes yet'), findsWidgets);
      expect(find.text('Select a note'), findsNothing);
    });

    testWidgets(
      'wide detail pane can be unselected from row, close, escape, and empty area',
      (tester) async {
        _setWideWindow(tester);

        await tester.pumpWidget(buildSubject(notes: [sampleNote]));
        await tester.pumpAndSettle();

        await tester.tapAt(const Offset(100, 100));
        await tester.pumpAndSettle();
        expect(find.text('Select a note'), findsNothing);

        await tester.tapAt(const Offset(100, 100));
        await tester.pumpAndSettle();
        expect(find.text('Select a note'), findsOneWidget);

        await tester.tapAt(const Offset(100, 100));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(AppIcons.close));
        await tester.pumpAndSettle();
        expect(find.text('Select a note'), findsOneWidget);

        await tester.tapAt(const Offset(100, 100));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Select a note'), findsOneWidget);

        await tester.tapAt(const Offset(100, 100));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(100, 500));
        await tester.pumpAndSettle();
        expect(find.text('Select a note'), findsOneWidget);
      },
    );

    testWidgets('renders color bar when colorHex is set', (tester) async {
      await tester.pumpWidget(buildSubject(notes: [sampleNote]));
      await tester.pumpAndSettle();

      // The color bar is a ColoredBox with a red color.
      final colored = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
      final colorBar = colored.where((c) => c.color == const Color(0xFFFF0000));
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

    testWidgets('opens create editor inline on wide layouts', (tester) async {
      _setWideWindow(tester);
      final notes = _FakeNotesRepository();

      await tester.pumpWidget(
        buildSubject(notes: const [], notesRepository: notes),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.add));
      await tester.pumpAndSettle();

      expect(find.byType(NoteEditor), findsOneWidget);
      expect(find.byType(NoteSheet), findsNothing);

      await tester.enterText(find.byType(EditableText).first, 'Inline note');
      await tester.pump();
      await tester.tap(find.byTooltip('Save note'));
      await tester.pumpAndSettle();

      expect(notes.created.single.title, 'Inline note');
      expect(find.byType(NoteEditor), findsNothing);
      expect(find.text('Inline note'), findsOneWidget);
    });

    testWidgets(
      'selecting another note confirms before closing dirty inline editor',
      (tester) async {
        _setWideWindow(tester);

        await tester.pumpWidget(buildSubject(notes: [sampleNote, noteNoColor]));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(AppIcons.add));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(EditableText).first, 'Draft note');
        await tester.pump();

        await tester.tap(find.text('Plain Note'));
        await tester.pumpAndSettle();

        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(NoteEditor), findsOneWidget);
        expect(find.text('Draft note'), findsOneWidget);

        await tester.tap(find.text('Plain Note'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();

        expect(find.byType(NoteEditor), findsNothing);
        expect(find.text('Select a note'), findsNothing);
        expect(find.text('Draft note'), findsNothing);
      },
    );

    testWidgets(
      'empty-area clear confirms before closing dirty inline editor',
      (tester) async {
        _setWideWindow(tester);

        await tester.pumpWidget(buildSubject(notes: [sampleNote]));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(AppIcons.add));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(EditableText).first, 'Draft note');
        await tester.pump();

        await tester.tapAt(const Offset(100, 500));
        await tester.pumpAndSettle();

        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(NoteEditor), findsOneWidget);
        expect(find.text('Draft note'), findsOneWidget);
      },
    );

    testWidgets('opens edit editor inline on wide layouts', (tester) async {
      _setWideWindow(tester);
      final notes = _FakeNotesRepository([sampleNote]);

      await tester.pumpWidget(
        buildSubject(notes: [sampleNote], notesRepository: notes),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Note'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(AppIcons.editOutlined));
      await tester.pumpAndSettle();

      expect(find.byType(NoteEditor), findsOneWidget);
      expect(find.byType(NoteSheet), findsNothing);
      expect(find.text('Test Note'), findsWidgets);
    });
  });
}

void _setWideWindow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeNotesRepository implements NotesRepository {
  _FakeNotesRepository([List<Note> initialNotes = const []]) {
    for (final note in initialNotes) {
      _notes[note.id] = note;
    }
  }

  final Map<String, Note> _notes = {};
  final created = <Note>[];
  final updated = <Note>[];

  @override
  Future<void> createNote(Note note) async {
    created.add(note);
    _notes[note.id] = note;
  }

  @override
  Future<void> deleteNote(String id) async {
    _notes.remove(id);
  }

  @override
  Future<List<Note>> getAllNotes() async => _notes.values.toList();

  @override
  Future<Note?> getNoteById(String id) async => _notes[id];

  @override
  Future<void> updateNote(Note note) async {
    updated.add(note);
    _notes[note.id] = note;
  }

  @override
  Stream<List<Note>> watchAllNotes() => Stream.value(_notes.values.toList());

  @override
  Stream<Note?> watchNoteById(String id) => Stream.value(_notes[id]);

  @override
  Stream<List<Note>> watchNotesForMember(String memberId) => Stream.value(
    _notes.values.where((note) => note.memberId == memberId).toList(),
  );

  @override
  Stream<List<Note>> watchRecentNotesForMember(
    String memberId, {
    int limit = 5,
  }) => Stream.value(
    _notes.values
        .where((note) => note.memberId == memberId)
        .take(limit)
        .toList(),
  );
}
