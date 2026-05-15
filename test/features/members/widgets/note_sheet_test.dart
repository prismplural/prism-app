import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/notes_repository.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/widgets/note_sheet.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  Member member({String id = 'member-1', String name = 'Alex'}) {
    return Member(id: id, name: name, createdAt: DateTime(2026, 1, 1));
  }

  testWidgets('localizes the empty headmate picker semantics label', (
    tester,
  ) async {
    Finder semanticsWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentFronterProvider.overrideWithValue(const AsyncValue.data(null)),
          systemSettingsProvider.overrideWithValue(
            const AsyncValue.data(
              SystemSettings(terminology: SystemTerminology.members),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en'), Locale('es')],
          locale: Locale('es'),
          home: Scaffold(body: NoteSheet()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      semanticsWithLabel('No hay integrante seleccionado. Toca para elegir'),
      findsOneWidget,
    );
  });

  testWidgets('does not show fallback terminology while settings load', (
    tester,
  ) async {
    final settings = StreamController<SystemSettings>();
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentFronterProvider.overrideWithValue(const AsyncValue.data(null)),
          systemSettingsProvider.overrideWith((ref) => settings.stream),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: Scaffold(body: NoteSheet()),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Add headmate'), findsNothing);
    expect(find.text('Add member'), findsNothing);

    settings.add(const SystemSettings(terminology: SystemTerminology.members));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Add member'), findsOneWidget);
    expect(find.text('Add headmate'), findsNothing);
  });

  testWidgets('defaults new notes to the current fronter', (tester) async {
    final currentFronter = member();
    final members = FakeMemberRepository()..seed([currentFronter]);
    final notes = _FakeNotesRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberRepositoryProvider.overrideWithValue(members),
          notesRepositoryProvider.overrideWithValue(notes),
          currentFronterProvider.overrideWithValue(
            AsyncValue.data(currentFronter),
          ),
          systemSettingsProvider.overrideWithValue(
            const AsyncValue.data(
              SystemSettings(terminology: SystemTerminology.members),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: Scaffold(body: NoteSheet()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Add member'), findsNothing);

    await tester.enterText(find.byType(EditableText).first, 'Front notes');
    await tester.pump();
    await tester.tap(find.byTooltip('Save note'));
    await tester.pumpAndSettle();

    expect(notes.created.single.memberId, 'member-1');
  });
}

class _FakeNotesRepository implements NotesRepository {
  final created = <Note>[];

  @override
  Future<void> createNote(Note note) async {
    created.add(note);
  }

  @override
  Future<void> deleteNote(String id) async {}

  @override
  Future<Note?> getNoteById(String id) async => null;

  @override
  Future<void> updateNote(Note note) async {}

  @override
  Stream<List<Note>> watchAllNotes() => Stream.value(created);

  @override
  Stream<Note?> watchNoteById(String id) => Stream.value(null);

  @override
  Stream<List<Note>> watchNotesForMember(String memberId) =>
      Stream.value(created.where((note) => note.memberId == memberId).toList());

  @override
  Stream<List<Note>> watchRecentNotesForMember(
    String memberId, {
    int limit = 5,
  }) => Stream.value(
    created.where((note) => note.memberId == memberId).take(limit).toList(),
  );
}
