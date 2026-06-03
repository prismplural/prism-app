import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/features/members/widgets/note_editor.dart';

/// Create or edit a note inside a full-screen [PrismSheet].
class NoteSheet extends StatelessWidget {
  const NoteSheet({super.key, this.note, this.memberId, this.scrollController});

  final Note? note;
  final String? memberId;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return NoteEditor(
      note: note,
      memberId: memberId,
      scrollController: scrollController,
    );
  }
}
