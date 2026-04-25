import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
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
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Provider to watch a single note by ID.
final noteByIdProvider =
    StreamProvider.autoDispose.family<Note?, String>((ref, id) {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onDispose(() => timer?.cancel());
  ref.onCancel(() {
    timer = Timer(const Duration(seconds: 30), link.close);
  });
  ref.onResume(() => timer?.cancel());
  final repo = ref.watch(notesRepositoryProvider);
  return repo.watchNoteById(id);
});

/// Full-screen detail view for a single note.
class NoteDetailScreen extends ConsumerWidget {
  const NoteDetailScreen({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final noteAsync = ref.watch(noteByIdProvider(noteId));

    return noteAsync.when(
      loading: () => PrismPageScaffold(
        topBar: PrismTopBar(title: l10n.memberNoteTitle, showBackButton: true),
        body: const PrismLoadingState(),
      ),
      error: (_, _) => PrismPageScaffold(
        topBar: PrismTopBar(title: l10n.memberNoteTitle, showBackButton: true),
        body: Center(child: Text(l10n.error)),
      ),
      data: (note) {
        if (note == null) {
          return PrismPageScaffold(
            topBar: PrismTopBar(title: l10n.memberNoteTitle, showBackButton: true),
            body: Center(child: Text(l10n.memberNoteNotFound)),
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
    final l10n = context.l10n;
    final dateFormat = DateFormat.yMMMd(context.dateLocale);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.editOutlined,
            tooltip: l10n.edit,
            onPressed: () => _openEditSheet(context),
          ),
          PrismTopBarAction(
            icon: AppIcons.deleteOutline,
            tooltip: l10n.delete,
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
                  borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(2)),
                ),
              ),
            Builder(builder: (context) {
              final displayTitle = note.title.isNotEmpty
                  ? note.title
                  : note.body.split('\n').first.trim();
              final isFallbackTitle = note.title.isEmpty;
              return Text(
                displayTitle.isNotEmpty ? displayTitle : l10n.memberNoteUntitled,
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
              dateFormat.format(note.date),
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
    final l10n = context.l10n;
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: l10n.memberNoteDeleteTitle,
      message: l10n.memberNoteDeleteMessage(note.title),
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (confirmed) {
      unawaited(ref.read(noteNotifierProvider.notifier).deleteNote(note.id));
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
