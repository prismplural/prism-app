import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/core/database/database_providers.dart';

/// Watches notes for a specific member.
final memberNotesProvider =
    StreamProvider.autoDispose.family<List<Note>, String>((ref, memberId) {
  final repo = ref.watch(notesRepositoryProvider);
  return repo.watchNotesForMember(memberId);
});

/// Watches recent notes for a member (limited, for preview sections).
final recentMemberNotesProvider =
    StreamProvider.autoDispose.family<List<Note>, String>((ref, memberId) {
  final repo = ref.watch(notesRepositoryProvider);
  return repo.watchRecentNotesForMember(memberId);
});

/// Watches all notes across all members.
final allNotesProvider = StreamProvider<List<Note>>((ref) {
  final repo = ref.watch(notesRepositoryProvider);
  return repo.watchAllNotes();
});

/// Note CRUD notifier.
class NoteNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  Future<void> createNote({
    required String title,
    required String body,
    String? colorHex,
    String? memberId,
    DateTime? date,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(notesRepositoryProvider);
      final now = DateTime.now();
      final note = Note(
        id: _uuid.v4(),
        title: title,
        body: body,
        colorHex: colorHex,
        memberId: memberId,
        date: date ?? now,
        createdAt: now,
        modifiedAt: now,
      );
      await repo.createNote(note);
    });
  }

  Future<void> updateNote(Note note) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(notesRepositoryProvider);
      await repo.updateNote(note.copyWith(modifiedAt: DateTime.now()));
    });
  }

  Future<void> deleteNote(String id) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(notesRepositoryProvider);
      await repo.deleteNote(id);
    });
  }
}

final noteNotifierProvider =
    AsyncNotifierProvider<NoteNotifier, void>(NoteNotifier.new);
