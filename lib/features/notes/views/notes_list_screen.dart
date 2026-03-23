import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/note_sheet.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

class NotesListScreen extends ConsumerWidget {
  const NotesListScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(allNotesProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: 'Notes',
        showBackButton: showBackButton,
        actions: [
          PrismTopBarAction(
            icon: Icons.add,
            tooltip: 'New note',
            onPressed: () => _showCreateSheet(context),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: notesAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (notes) {
          if (notes.isEmpty) {
            return EmptyState(
              icon: Icons.note_outlined,
              title: 'No notes yet',
              subtitle: 'Create notes to keep track of thoughts and observations',
              actionLabel: 'New Note',
              onAction: () => _showCreateSheet(context),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.only(
              top: 8,
              left: 16,
              right: 16,
              bottom: NavBarInset.of(context),
            ),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _NoteCard(note: note),
              );
            },
          );
        },
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => NoteSheet(
        scrollController: scrollController,
      ),
    );
  }
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.note});

  final Note note;

  static final _dateFormat = DateFormat.yMMMd();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Look up the member if this note is associated with one
    final memberAsync = note.memberId != null
        ? ref.watch(memberByIdProvider(note.memberId!))
        : null;
    final member = memberAsync?.value;

    Color? colorBar;
    if (note.colorHex != null) {
      try {
        colorBar =
            Color(int.parse(note.colorHex!.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }

    return GestureDetector(
      onTap: () {
        final location = GoRouterState.of(context).uri.path;
        final isTopLevel = location.startsWith(AppRoutePaths.notes) &&
            !location.startsWith(AppRoutePaths.settings);
        context.push(
          isTopLevel
              ? AppRoutePaths.note(note.id)
              : '/settings/notes/${note.id}',
        );
      },
      child: PrismSectionCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (colorBar != null)
              Container(
                width: 4,
                height: 56,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: colorBar,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(builder: (context) {
                    final displayTitle = note.title.isNotEmpty
                        ? note.title
                        : note.body.split('\n').first.trim();
                    final isFallbackTitle = note.title.isEmpty;
                    return Text(
                      displayTitle.isNotEmpty ? displayTitle : 'Untitled',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight:
                            isFallbackTitle ? FontWeight.normal : FontWeight.w600,
                        fontStyle:
                            isFallbackTitle ? FontStyle.italic : FontStyle.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  }),
                  if (note.body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      note.body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _dateFormat.format(note.date),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (member != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: MemberAvatar(
                  avatarImageData: member.avatarImageData,
                  emoji: member.emoji,
                  customColorEnabled: member.customColorEnabled,
                  customColorHex: member.customColorHex,
                  size: 28,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
