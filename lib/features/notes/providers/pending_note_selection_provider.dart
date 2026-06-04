import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A one-shot request to open a specific note in the notes screen's detail pane
/// on wide windows. Call [PendingNoteSelectionNotifier.request], then navigate
/// to the notes tab; `NotesListScreen` consumes it (selecting the note in its
/// pane) and [PendingNoteSelectionNotifier.clear]s it. Lets other screens —
/// e.g. the media-usage list — deep-link a note into the pane instead of
/// pushing it full-screen.
class PendingNoteSelectionNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String noteId) => state = noteId;
  void clear() => state = null;
}

final pendingNoteSelectionProvider =
    NotifierProvider<PendingNoteSelectionNotifier, String?>(
      PendingNoteSelectionNotifier.new,
    );
