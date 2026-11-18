// The notes list pins one header: the top bar plus, when a search or member filter
// is active, the filter bar whose height is the search field's line box plus its
// content padding, the chip strip's tallest chip (label line or the text-scaled
// avatar, plus the chip's own border), the gap between them and the bottom
// padding.
//
// Desired behaviour, asserted on the real `NotesListScreen`: the pinned band is
// sized from the same measurements its children use, so the filter bar (field
// and chips) is painted inside the band at full size, before and after the list
// scrolls, and the band re-measures when the text scale changes.
//
// `NotesFilterBar` is exercised through the screen rather than by calling its own
// size API, so the assertion covers what is actually painted.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/notes_repository.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/notes/views/notes_list_screen.dart';
import 'package:prism_plurality/features/notes/widgets/notes_filter_bar.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

import '../../helpers/fake_repositories.dart';
import 'chrome_text_scale_harness.dart';

class _FakeNotesRepository implements NotesRepository {
  _FakeNotesRepository(List<Note> initialNotes) {
    for (final note in initialNotes) {
      _notes[note.id] = note;
    }
  }

  final Map<String, Note> _notes = {};

  @override
  Future<void> createNote(Note note) async => _notes[note.id] = note;

  @override
  Future<void> deleteNote(String id) async => _notes.remove(id);

  @override
  Future<List<Note>> getAllNotes() async => _notes.values.toList();

  @override
  Future<Note?> getNoteById(String id) async => _notes[id];

  @override
  Future<void> updateNote(Note note) async => _notes[note.id] = note;

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

final _note = Note(
  id: 'note-1',
  title: 'Test Note',
  body: 'Some body text',
  colorHex: '#FF0000',
  memberId: 'mem-a',
  date: DateTime(2026, 3, 21),
  createdAt: DateTime(2026, 3, 21),
  modifiedAt: DateTime(2026, 3, 21),
);

final _alice = Member(id: 'mem-a', name: 'Alice', createdAt: DateTime(2024));
final _bob = Member(id: 'mem-b', name: 'Bob', createdAt: DateTime(2024));

Widget _subject({
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  Locale locale = const Locale('en'),
  bool boldText = false,
}) {
  final notes = [_note];
  final members = [_alice, _bob];
  return ProviderScope(
    overrides: [
      memberRepositoryProvider.overrideWithValue(
        FakeMemberRepository()..seed(members),
      ),
      notesRepositoryProvider.overrideWithValue(_FakeNotesRepository(notes)),
      allNotesProvider.overrideWith((ref) => Stream.value(notes)),
      activeMemberListProvider.overrideWith((ref) => Stream.value(members)),
      currentFronterProvider.overrideWithValue(const AsyncValue.data(null)),
      systemSettingsProvider.overrideWithValue(
        const AsyncValue.data(SystemSettings()),
      ),
    ],
    child: chromeApp(
      const NotesListScreen(),
      system: system,
      app: app,
      fontFamily: fontFamily,
      locale: locale,
      boldText: boldText,
    ),
  );
}

/// The bottom of the pinned band, read from the header sliver's own geometry so
/// it does not depend on what the list renders first.
double _bandBottom(WidgetTester tester, String label) {
  final bar = find.byType(PrismTopBar);
  expect(bar, findsOneWidget, reason: '$label: one top bar');
  return tester.getRect(bar).top + pinnedBandHeight(tester);
}

/// The screen's own localizations, so a non-English locale finds the real control
/// instead of a hardcoded English tooltip.
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(NotesListScreen)));

Future<void> _enableSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip(_l10n(tester).memberNoteSearchNotes));
  await tester.pumpAndSettle();
  expect(find.byType(NotesFilterBar), findsOneWidget);
}

Future<void> _selectMemberFilter(WidgetTester tester) async {
  await tester.tap(find.byTooltip(_l10n(tester).memberNoteFilterByMember));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(MemberSearchSheet),
      matching: find.text('Alice'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip &&
          (widget.message?.startsWith('Confirm selected ') ?? false),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadChromeFonts();
  });

  for (final (system, app, label) in chromeScales) {
    // The 60dp search slot holds the field's content padding plus its line box and
    // the 8dp bottom padding. Whether it still does is read from the rendered field
    // below, not from the scale.
    final composedScale = system * app;

    testWidgets('notes search field stays inside the pinned band ($label)', (
      tester,
    ) async {
      useWindow(tester, compactPhone);
      await tester.pumpWidget(_subject(system: system, app: app));
      await tester.pumpAndSettle();

      // With no filter bar the pinned header is the bare top bar; its height is the
      // bar's own, whatever the scale.
      expect(
        _bandBottom(tester, label),
        greaterThanOrEqualTo(PrismTokens.topBarHeight - 0.5),
        reason: '$label: the bar alone keeps at least its own height',
      );

      await _enableSearch(tester);

      final bandBottom = _bandBottom(tester, label);
      final filterRect = tester.getRect(find.byType(NotesFilterBar));
      expect(
        filterRect.bottom,
        lessThanOrEqualTo(bandBottom + 0.5),
        reason:
            '$label: the filter bar (bottom ${filterRect.bottom.toStringAsFixed(1)}) '
            'is clipped by the pinned band (bottom ${bandBottom.toStringAsFixed(1)})',
      );
      // The slot is preserved only while the field really fits inside it; the
      // field's own measured height decides, not the scale.
      final fieldSlotFits =
          tester.getRect(find.byType(PrismTextField)).height +
              NotesFilterBar.searchSlotBottomPadding <=
          NotesFilterBar.searchSlotHeight + 0.01;
      final barHeight = tester.getRect(find.byType(PrismTopBar)).height;
      if (fieldSlotFits) {
        expect(
          bandBottom,
          closeTo(barHeight + NotesFilterBar.searchSlotHeight, 0.5),
          reason:
              '$label: the search slot keeps its 60dp when the field fits, so the '
              'band is the bar plus that slot',
        );
      } else {
        expect(
          bandBottom,
          greaterThan(barHeight + NotesFilterBar.searchSlotHeight + 0.5),
          reason:
              '$label: the field needs more than the 60dp slot, so the band must '
              'grow past it',
        );
      }

      // The hint paragraph must keep the line box the field's own text needs.
      final fieldText = expectFullSizeText(
        tester,
        'Search notes…',
        label: '$label (search field)',
      );
      expect(
        fieldText.bottom,
        lessThanOrEqualTo(bandBottom + 0.5),
        reason: '$label: the search text is painted below the pinned band',
      );
      expectNoLayoutException(tester, '$label (search)');
    });
  }

  // The chip strip's own slot is 44dp today and needs 50dp from 1.5x on. Run at
  // 1.5x on a taller window: the defect under test is the header slot, and the
  // member-picker flow used to select the filter must not also be squeezed by
  // the compact phone's height.
  testWidgets('notes member-filter chips stay inside the pinned band', (
    tester,
  ) async {
    useWindow(tester, const Size(320, 900));
    await tester.pumpWidget(_subject(system: 1.5, app: 1.0));
    await tester.pumpAndSettle();

    await _selectMemberFilter(tester);

    final bandBottom = _bandBottom(tester, 'chips');
    final chipText = expectFullSizeText(
      tester,
      'Alice',
      label: 'chip label',
      finder: find.descendant(
        of: find.byType(NotesFilterBar),
        matching: find.text('Alice'),
      ),
    );
    expect(
      chipText.bottom,
      lessThanOrEqualTo(bandBottom + 0.5),
      reason:
          'the member chip (bottom ${chipText.bottom.toStringAsFixed(1)}) is '
          'painted below the pinned band (bottom ${bandBottom.toStringAsFixed(1)})',
    );
    final filterRect = tester.getRect(find.byType(NotesFilterBar));
    expect(
      filterRect.bottom,
      lessThanOrEqualTo(bandBottom + 0.5),
      reason: 'the chip strip is clipped by the pinned band',
    );
    expectNoLayoutException(tester, 'chips');
  });

  testWidgets('notes pinned filter header keeps the field visible after the '
      'list scrolls', (tester) async {
    useWindow(tester, compactPhone);
    await tester.pumpWidget(_subject(system: 2.25, app: 1.5));
    await tester.pumpAndSettle();
    await _enableSearch(tester);

    final before = tester.getRect(find.byType(NotesFilterBar));
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    final after = tester.getRect(find.byType(NotesFilterBar));

    expect(
      after.top,
      closeTo(before.top, 0.5),
      reason: 'the filter bar is pinned: it must not scroll away',
    );
    expect(
      after.bottom,
      lessThanOrEqualTo(_bandBottom(tester, 'scrolled') + 0.5),
      reason: 'the pinned filter bar stays inside the band while scrolled',
    );
    expectFullSizeText(tester, 'Search notes…', label: 'scrolled search field');
    expectNoLayoutException(tester, 'scrolled');
  });

  // D3 demonstration: a pinned composite that grows must not outgrow the
  // viewport. Landscape-ish window with the keyboard up, search active: today the
  // pinned band is a fixed 126dp against a 220dp viewport and its own content
  // needs 179dp, so it overflows and squeezes the list to nothing. Desired: no
  // clipping, and the note content stays reachable (header scrolls).
  testWidgets('notes header and content stay reachable on a short viewport with '
      'the keyboard up', (tester) async {
    useWindow(tester, const Size(320, 360), keyboardInset: 140);
    await tester.pumpWidget(_subject(system: 2.25, app: 1.5));
    await tester.pumpAndSettle();
    await _enableSearch(tester);

    expectNoLayoutException(tester, 'short viewport');
    expectFullSizeText(tester, 'Search notes…', label: 'short viewport');

    // Drive the outer scroll position directly: on a viewport this short the
    // header can be taller than the viewport, so a drag cannot be relied on to
    // hit the inner list.
    final outer = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(
      outer.position.maxScrollExtent,
      greaterThan(0),
      reason: 'the header and the list must be scrollable, i.e. reachable',
    );
    outer.position.jumpTo(outer.position.maxScrollExtent);
    await tester.pumpAndSettle();

    // The header itself is not read here: once it scrolls away the sliver may not
    // build it at all, so a `getRect` on the bar would fail for a legitimate cull.
    // The scroll offset is the honest witness that it moved instead of pinning.
    expect(
      outer.position.pixels,
      greaterThan(0),
      reason:
          'the composite header scrolls with the content instead of staying '
          'pinned and squeezing the list to nothing',
    );
    final noteCard = find.text('Test Note');
    expect(
      noteCard,
      findsOneWidget,
      reason: 'the note list is reachable after scrolling on a short viewport',
    );
    final noteRect = tester.getRect(noteCard);
    final listRect = tester.getRect(find.byType(ListView));
    expect(
      noteRect.top,
      greaterThanOrEqualTo(listRect.top - 0.5),
      reason:
          'the note content is inside the list viewport, not clipped above it',
    );
    expect(
      noteRect.bottom,
      lessThanOrEqualTo(listRect.bottom + 0.5),
      reason: 'the note content is reachable, not clipped out of the viewport',
    );
    expectNoLayoutException(tester, 'short viewport after scroll');
  });

  testWidgets('notes pinned header re-measures when the text scale changes', (
    tester,
  ) async {
    useWindow(tester, compactPhone);
    await tester.pumpWidget(_subject(system: 1.0, app: 1.0));
    await tester.pumpAndSettle();
    await _enableSearch(tester);
    final before = _bandBottom(tester, 'before');

    await tester.pumpWidget(_subject(system: 2.25, app: 1.5));
    await tester.pumpAndSettle();

    final after = _bandBottom(tester, 'after');
    expect(
      after,
      greaterThan(before),
      reason: 'the pinned band must follow the new text scale',
    );
    expectFullSizeText(tester, 'Search notes…', label: 'after scale change');
    expectNoLayoutException(tester, 'after scale change');
  });

  // The pinned band must be exactly what the filter bar paints, not merely an
  // envelope around it: a bar that over-reserves is as wrong as one that clips.
  for (final fontFamily in ['Lexend', 'OpenDyslexic']) {
    for (final (system, app, label) in [
      (1.0, 1.5, '1.5x'),
      (1.5, 1.5, '2.25x'),
    ]) {
      testWidgets('notes band equals the rendered bar plus filter bar '
          '($label, $fontFamily)', (tester) async {
        useWindow(tester, compactPhone);
        await tester.pumpWidget(
          _subject(system: system, app: app, fontFamily: fontFamily),
        );
        await tester.pumpAndSettle();
        await _enableSearch(tester);

        final barRect = tester.getRect(find.byType(PrismTopBar));
        final filterRect = tester.getRect(find.byType(NotesFilterBar));
        final band = pinnedBandHeight(tester);
        expect(
          band,
          closeTo(barRect.height + filterRect.height, 0.5),
          reason:
              '$label/$fontFamily: the pinned band ($band) must equal the bar '
              '(${barRect.height}) plus the filter bar (${filterRect.height})',
        );
        expectNoLayoutException(tester, '$label/$fontFamily notes band');
      });
    }
  }

  // Cache parity: the same child at the same width with bold text or a
  // different locale must still produce a band equal to what is painted.
  for (final variant in [
    (label: 'bold text', boldText: true, locale: const Locale('en')),
    (label: 'Spanish locale', boldText: false, locale: const Locale('es')),
  ]) {
    testWidgets('notes band stays equal under ${variant.label}', (
      tester,
    ) async {
      useWindow(tester, compactPhone);
      await tester.pumpWidget(
        _subject(
          system: 1.0,
          app: 1.5,
          boldText: variant.boldText,
          locale: variant.locale,
        ),
      );
      await tester.pumpAndSettle();
      await _enableSearch(tester);

      final barRect = tester.getRect(find.byType(PrismTopBar));
      final filterRect = tester.getRect(find.byType(NotesFilterBar));
      final band = pinnedBandHeight(tester);
      expect(
        band,
        closeTo(barRect.height + filterRect.height, 0.5),
        reason:
            '${variant.label}: the band must be the rendered bar plus filter bar',
      );
      expectNoLayoutException(tester, variant.label);
    });
  }
}
