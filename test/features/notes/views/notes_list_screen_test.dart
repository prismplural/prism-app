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
import 'package:prism_plurality/shared/widgets/member_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/notes/views/notes_list_screen.dart';
import 'package:prism_plurality/features/notes/widgets/notes_filter_bar.dart';

import '../../../helpers/fake_repositories.dart';

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

  final sampleMember = Member(
    id: 'mem-a',
    name: 'Alice',
    emoji: '',
    createdAt: DateTime(2024),
  );

  final secondMember = Member(
    id: 'mem-b',
    name: 'Bob',
    emoji: '',
    createdAt: DateTime(2024),
  );

  Widget buildSubject({
    List<Note> notes = const [],
    List<Member> members = const [],
    _FakeNotesRepository? notesRepository,
  }) {
    final repository = notesRepository ?? _FakeNotesRepository(notes);
    final memberRepository = FakeMemberRepository()..seed(members);
    return ProviderScope(
      overrides: [
        memberRepositoryProvider.overrideWithValue(memberRepository),
        notesRepositoryProvider.overrideWithValue(repository),
        allNotesProvider.overrideWith((ref) => Stream.value(notes)),
        activeMemberListProvider.overrideWith((ref) => Stream.value(members)),
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

    testWidgets('note card renders member as accented Prism chip', (
      tester,
    ) async {
      final member = sampleMember.copyWith(
        customColorEnabled: true,
        customColorHex: '#12AB34',
      );
      final note = sampleNote.copyWith(memberId: member.id);

      await tester.pumpWidget(buildSubject(notes: [note], members: [member]));
      await tester.pumpAndSettle();

      final memberChip = tester.widget<MemberChip>(find.byType(MemberChip));
      expect(memberChip.style, MemberChipStyle.inline);

      final chip = tester
          .widgetList<PrismChip>(find.byType(PrismChip))
          .singleWhere((chip) => chip.label == 'Alice');
      expect(chip.selected, isTrue);
      expect(chip.selectedColor, const Color(0xFF12AB34));
      expect(chip.variant, PrismChipVariant.inline);
    });

    testWidgets('note card previews resolve member mention tokens', (
      tester,
    ) async {
      const aliceId = '11111111-2222-3333-4444-555555555555';
      final alice = sampleMember.copyWith(id: aliceId, name: 'Alice');
      final note = sampleNote.copyWith(
        title: '',
        body: 'Talked to @[$aliceId]\nsecond line with @[$aliceId]',
      );

      await tester.pumpWidget(buildSubject(notes: [note], members: [alice]));
      await tester.pumpAndSettle();

      expect(find.text('Talked to @Alice'), findsOneWidget);
      expect(find.textContaining('@[$aliceId]'), findsNothing);
      expect(find.textContaining('@Alice'), findsWidgets);
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

    testWidgets('wide detail delete clears pane without popping app route', (
      tester,
    ) async {
      _setWideWindow(tester);
      final notes = _FakeNotesRepository([sampleNote]);

      await tester.pumpWidget(
        buildSubject(notes: [sampleNote], notesRepository: notes),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Note'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.deleteOutline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(notes.deletedIds, ['note-1']);
      expect(find.byType(NotesListScreen), findsOneWidget);
      expect(find.text('Select a note'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('NotesListScreen search and filter', () {
    testWidgets('search icon is present in top bar', (tester) async {
      await tester.pumpWidget(
        buildSubject(notes: [sampleNote], members: [sampleMember]),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Search notes'), findsOneWidget);
    });

    testWidgets('filter icon is present in top bar', (tester) async {
      await tester.pumpWidget(
        buildSubject(notes: [sampleNote], members: [sampleMember]),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Filter by member'), findsOneWidget);
    });

    testWidgets('filter icon is enabled even when no members exist', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject(notes: [sampleNote], members: []));
      await tester.pumpAndSettle();

      // The filter button should still be enabled so users can access
      // the "No member" option even with no active members.
      final filterIconFinder = find.byIcon(AppIcons.filterList);
      expect(filterIconFinder, findsOneWidget);
      final buttonFinder = find.ancestor(
        of: filterIconFinder,
        matching: find.byType(PrismGlassIconButton),
      );
      final filterButton = tester.widget<PrismGlassIconButton>(buttonFinder);
      expect(filterButton.onPressed, isNotNull);
    });

    testWidgets('filter sheet includes active members', (tester) async {
      await tester.pumpWidget(
        buildSubject(notes: [sampleNote], members: [sampleMember]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Filter by member'));
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('No member'), findsOneWidget);
    });

    testWidgets('creating while member-filtered does not prefill author', (
      tester,
    ) async {
      final notes = _FakeNotesRepository([sampleNote]);

      await tester.pumpWidget(
        buildSubject(
          notes: [sampleNote],
          members: [sampleMember],
          notesRepository: notes,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Filter by member'));
      await tester.pumpAndSettle();
      await tester.tap(_memberSearchSheetText('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(_confirmSelectedMembersButton());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.add));
      await tester.pumpAndSettle();

      expect(find.byType(NoteSheet), findsOneWidget);

      await tester.enterText(find.byType(EditableText).first, 'Filtered note');
      await tester.pump();
      await tester.tap(find.byTooltip('Save note'));
      await tester.pumpAndSettle();

      expect(notes.created.single.title, 'Filtered note');
      expect(notes.created.single.memberId, isNull);
    });

    testWidgets('member filter supports selecting multiple members', (
      tester,
    ) async {
      final aliceNote = sampleNote.copyWith(memberId: 'mem-a');
      final bobNote = noteNoColor.copyWith(memberId: 'mem-b');
      final noMemberNote = Note(
        id: 'note-3',
        title: 'Unassigned Note',
        body: 'No author here',
        date: DateTime(2026, 3, 19),
        createdAt: DateTime(2026, 3, 19),
        modifiedAt: DateTime(2026, 3, 19),
      );

      await tester.pumpWidget(
        buildSubject(
          notes: [aliceNote, bobNote, noMemberNote],
          members: [sampleMember, secondMember],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Filter by member'));
      await tester.pumpAndSettle();
      await tester.tap(_memberSearchSheetText('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(_memberSearchSheetText('Bob'));
      await tester.pumpAndSettle();
      await tester.tap(_confirmSelectedMembersButton());
      await tester.pumpAndSettle();

      expect(find.text('Test Note'), findsOneWidget);
      expect(find.text('Plain Note'), findsOneWidget);
      expect(find.text('Unassigned Note'), findsNothing);
      expect(find.byType(NotesFilterBar), findsOneWidget);
      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Bob'), findsWidgets);
    });

    testWidgets('member filter supports selecting no member', (tester) async {
      final aliceNote = sampleNote.copyWith(memberId: 'mem-a');
      final noMemberNote = noteNoColor.copyWith(
        id: 'note-3',
        title: 'Unassigned Note',
        memberId: null,
      );

      await tester.pumpWidget(
        buildSubject(notes: [aliceNote, noMemberNote], members: [sampleMember]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Filter by member'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No member'));
      await tester.pumpAndSettle();
      await tester.tap(_confirmSelectedMembersButton());
      await tester.pumpAndSettle();

      expect(find.text('Test Note'), findsNothing);
      expect(find.text('Unassigned Note'), findsOneWidget);
      expect(find.byType(NotesFilterBar), findsOneWidget);
      expect(find.text('No member'), findsOneWidget);
    });

    testWidgets('tapping search icon shows filter bar inside pinned top bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(notes: [sampleNote], members: [sampleMember]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search notes'));
      await tester.pumpAndSettle();

      final searchAction = tester
          .widgetList<PrismTopBarAction>(find.byType(PrismTopBarAction))
          .singleWhere((action) => action.tooltip == 'Search notes');
      expect(searchAction.accentIcon, isTrue);
      expect(searchAction.tint, isNotNull);
      expect(find.byType(NotesFilterBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SliverPinnedTopBar),
          matching: find.byType(NotesFilterBar),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping search icon again hides filter bar', (tester) async {
      await tester.pumpWidget(
        buildSubject(notes: [sampleNote], members: [sampleMember]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search notes'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesFilterBar), findsOneWidget);

      await tester.tap(find.byTooltip('Search notes'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesFilterBar), findsNothing);
    });

    testWidgets('filtered empty state differs from no-notes empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(notes: [sampleNote], members: [sampleMember]),
      );
      await tester.pumpAndSettle();

      // Toggle search on and type something that won't match
      await tester.tap(find.byTooltip('Search notes'));
      await tester.pumpAndSettle();

      final textField = find.byType(PrismTextField);
      await tester.enterText(textField, 'xyzzynotfound');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('No notes match your search'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);
    });

    testWidgets('search matches resolved member mentions', (tester) async {
      const mentionedMemberId = '11111111-2222-3333-4444-555555555555';
      final mentionedMember = Member(
        id: mentionedMemberId,
        name: 'June',
        emoji: '',
        createdAt: DateTime(2024),
      );
      final note = sampleNote.copyWith(
        title: 'Self search',
        body: 'Eugh. @[$mentionedMemberId]',
      );

      await tester.pumpWidget(
        buildSubject(notes: [note], members: [mentionedMember]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search notes'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(PrismTextField), 'june');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Self search'), findsOneWidget);
      expect(find.textContaining('Eugh. @June'), findsOneWidget);
      expect(find.text('No notes match your search'), findsNothing);
    });

    testWidgets('add action button is still present', (tester) async {
      await tester.pumpWidget(
        buildSubject(notes: [sampleNote], members: [sampleMember]),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(AppIcons.add), findsOneWidget);
    });
  });
}

void _setWideWindow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _confirmSelectedMembersButton() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Tooltip &&
        (widget.message?.startsWith('Confirm selected ') ?? false),
  );
}

Finder _memberSearchSheetText(String text) {
  return find.descendant(
    of: find.byType(MemberSearchSheet),
    matching: find.text(text),
  );
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
  final deletedIds = <String>[];

  @override
  Future<void> createNote(Note note) async {
    created.add(note);
    _notes[note.id] = note;
  }

  @override
  Future<void> deleteNote(String id) async {
    deletedIds.add(id);
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
