import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/members/widgets/note_sheet.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Provider to watch a single note by ID.
final noteByIdProvider =
    StreamProvider.family<Note?, String>((ref, id) async* {
  final repo = ref.watch(notesRepositoryProvider);
  final note = await repo.getNoteById(id);
  yield note;
});

/// Full-screen detail view for a single note.
class NoteDetailScreen extends ConsumerWidget {
  const NoteDetailScreen({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noteAsync = ref.watch(noteByIdProvider(noteId));

    return noteAsync.when(
      loading: () => const PrismPageScaffold(
        topBar: PrismTopBar(title: 'Note', showBackButton: true),
        body: PrismLoadingState(),
      ),
      error: (e, _) => PrismPageScaffold(
        topBar: const PrismTopBar(title: 'Note', showBackButton: true),
        body: Center(child: Text('Error: $e')),
      ),
      data: (note) {
        if (note == null) {
          return const PrismPageScaffold(
            topBar: PrismTopBar(title: 'Note', showBackButton: true),
            body: Center(child: Text('Note not found')),
          );
        }
        return _NoteDetailBody(note: note);
      },
    );
  }
}

class _NoteDetailBody extends ConsumerWidget {
  const _NoteDetailBody({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.editOutlined,
            tooltip: 'Edit',
            onPressed: () => _openEditSheet(context),
          ),
          PrismTopBarAction(
            icon: AppIcons.deleteOutline,
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 16, 24, NavBarInset.of(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note.colorHex != null)
              Container(
                width: double.infinity,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _parseColor(note.colorHex!),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Builder(builder: (context) {
              final displayTitle = note.title.isNotEmpty
                  ? note.title
                  : note.body.split('\n').first.trim();
              final isFallbackTitle = note.title.isEmpty;
              return Text(
                displayTitle.isNotEmpty ? displayTitle : 'Untitled',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight:
                      isFallbackTitle ? FontWeight.normal : FontWeight.bold,
                  fontStyle:
                      isFallbackTitle ? FontStyle.italic : FontStyle.normal,
                ),
              );
            }),
            const SizedBox(height: 8),
            Text(
              DateFormat.yMMMd().format(note.date),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            MarkdownText(
              data: note.body,
              enabled: true,
              baseStyle: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  void _openEditSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => NoteSheet(
        note: note,
        scrollController: scrollController,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Delete note?',
      message: 'Are you sure you want to delete "${note.title}"? '
          'This action cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) {
      ref.read(noteNotifierProvider.notifier).deleteNote(note.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Color _parseColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 7) buffer.write('FF');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
