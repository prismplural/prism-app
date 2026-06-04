import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/markdown/markdown_preview.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/notes/providers/pending_note_selection_provider.dart';
import 'package:prism_plurality/features/members/widgets/note_editor.dart';
import 'package:prism_plurality/features/members/widgets/note_sheet.dart';
import 'package:prism_plurality/shared/markdown/spoiler_syntax.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/features/members/views/note_detail_screen.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/list_detail_layout.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

enum NotesListBranch { settings, notes }

class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({
    super.key,
    this.showBackButton = true,
    this.branch = NotesListBranch.notes,
  });

  final bool showBackButton;
  final NotesListBranch branch;

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen>
    with ListDetailSelectionState<NotesListScreen> {
  _NoteEditorPane? _editorPane;
  final _noteEditorController = NoteEditorController();
  int _editorRevision = 0;

  String _notePath(String id) => switch (widget.branch) {
    NotesListBranch.settings => AppRoutePaths.settingsNote(id),
    NotesListBranch.notes => AppRoutePaths.note(id),
  };

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(allNotesProvider);
    final l10n = context.l10n;

    // Honour a one-shot request to open a specific note in the pane (e.g. from
    // the media-usage list), applied after this frame so it can setState
    // safely. Only issued while the deep-linking sheet is up, i.e. on wide
    // windows where the pane is shown.
    final pendingNote = ref.watch(pendingNoteSelectionProvider);
    if (pendingNote != null && pendingNote != selectedDetailId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(pendingNoteSelectionProvider.notifier).clear();
        setState(() => selectedDetailId = pendingNote);
      });
    }

    // Each pane owns its top bar so they sit side by side in two-pane mode:
    // the notes bar is scoped to the list pane, and the note detail fills its
    // whole pane (its own bar included).
    return ListDetailLayout(
      onClearSelection: () => unawaited(_clearDetailPane()),
      detail: (context) => _buildDetailPane(),
      list: (context, isWide) {
        setListDetailWide(isWide);
        return PrismPageScaffold(
          topBar: PrismTopBar(
            title: l10n.memberSectionNotes,
            showBackButton: widget.showBackButton,
            actions: [
              PrismTopBarAction(
                icon: AppIcons.add,
                tooltip: l10n.memberAddNoteTooltip,
                onPressed: () => unawaited(_openCreateNote(context)),
              ),
            ],
          ),
          bodyPadding: EdgeInsets.zero,
          body: notesAsync.when(
            loading: () => const PrismLoadingState(),
            error: (_, _) => Center(child: Text(context.l10n.error)),
            data: (notes) {
              if (notes.isEmpty) {
                return EmptyState(
                  icon: Icon(AppIcons.noteOutlined),
                  title: l10n.memberNoteNoNotesYet,
                  subtitle: l10n.memberNoteEmptySubtitle,
                  actionLabel: l10n.memberNoteTitle,
                  onAction: () => unawaited(_openCreateNote(context)),
                );
              }

              return ListView.builder(
                padding: EdgeInsets.only(
                  top: 8,
                  left: 16,
                  right: 16,
                  // +16 so the last card clears the nav bar's gradient fade,
                  // which extends 10px above NavBarInset.bottomInset.
                  bottom: NavBarInset.of(context) + 16,
                ),
                itemCount: notes.length,
                itemBuilder: (context, index) {
                  final note = notes[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _NoteCard(
                      note: note,
                      selected: isDetailSelected(note.id),
                      onTap: () => unawaited(_openNote(context, note.id)),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  /// Wide-layout note detail/editor pane.
  Widget _buildDetailPane() {
    final editorPane = _editorPane;
    if (editorPane != null) {
      return NoteEditor(
        key: ValueKey('note-editor-${editorPane.revision}'),
        note: editorPane.note,
        memberId: editorPane.memberId,
        controller: _noteEditorController,
        onSaved: _finishInlineEditor,
        onCancel: _closeInlineEditor,
      );
    }

    final id = selectedDetailId;
    if (id == null) {
      final notesAsync = ref.watch(allNotesProvider);
      return notesAsync.when(
        loading: () => const PrismLoadingState(),
        error: (_, _) => Center(child: Text(context.l10n.error)),
        data: (notes) => notes.isEmpty
            ? EmptyState(
                icon: Icon(AppIcons.noteOutlined),
                title: context.l10n.memberNoteNoNotesYet,
                subtitle: context.l10n.memberNoteEmptySubtitle,
              )
            : EmptyState(
                icon: Icon(AppIcons.noteOutlined),
                title: context.l10n.memberNoteSelectEmptyTitle,
                subtitle: context.l10n.memberNoteSelectEmptySubtitle,
              ),
      );
    }
    // ListDetailLayout isolates this pane's NestedScrollView for us.
    return NoteDetailScreen(
      key: ValueKey(id),
      noteId: id,
      showBackButton: false,
      onEditNote: _openInlineEditorForNote,
    );
  }

  Future<void> _openCreateNote(BuildContext context) async {
    if (isDetailPaneVisible) {
      final canCloseEditor = await _confirmCloseInlineEditorIfNeeded();
      if (!canCloseEditor || !mounted) return;

      setState(() {
        selectedDetailId = null;
        _editorPane = _NoteEditorPane.create(revision: ++_editorRevision);
      });
      return;
    }

    unawaited(
      PrismSheet.showFullScreen(
        context: context,
        builder: (context, scrollController) =>
            NoteSheet(scrollController: scrollController),
      ),
    );
  }

  Future<void> _openNote(BuildContext context, String id) async {
    if (isDetailPaneVisible) {
      final canCloseEditor = await _confirmCloseInlineEditorIfNeeded();
      if (!canCloseEditor || !mounted) return;

      setState(() {
        selectedDetailId = selectedDetailId == id && _editorPane == null
            ? null
            : id;
        _editorPane = null;
      });
      return;
    }

    unawaited(context.push(_notePath(id)));
  }

  void _openInlineEditorForNote(Note note) {
    setState(() {
      selectedDetailId = note.id;
      _editorPane = _NoteEditorPane.edit(
        note: note,
        revision: ++_editorRevision,
      );
    });
  }

  void _finishInlineEditor(Note note) {
    setState(() {
      selectedDetailId = note.id;
      _editorPane = null;
    });
  }

  void _closeInlineEditor() {
    setState(() => _editorPane = null);
  }

  Future<void> _clearDetailPane() async {
    if (_editorPane != null) {
      final canCloseEditor = await _confirmCloseInlineEditorIfNeeded();
      if (!canCloseEditor || !mounted) return;
      setState(() => _editorPane = null);
      return;
    }
    if (selectedDetailId == null) return;
    setState(() => selectedDetailId = null);
  }

  Future<bool> _confirmCloseInlineEditorIfNeeded() {
    if (_editorPane == null) return Future.value(true);
    return _noteEditorController.confirmDiscardIfNeeded();
  }
}

class _NoteEditorPane {
  const _NoteEditorPane._({required this.revision, this.note, this.memberId});

  factory _NoteEditorPane.create({required int revision, String? memberId}) =>
      _NoteEditorPane._(revision: revision, memberId: memberId);

  factory _NoteEditorPane.edit({required Note note, required int revision}) =>
      _NoteEditorPane._(revision: revision, note: note);

  final int revision;
  final Note? note;
  final String? memberId;
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({
    required this.note,
    required this.selected,
    required this.onTap,
  });

  final Note note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    // Locale-aware date format — must be a local variable, not static.
    final dateFormat = DateFormat.yMMMd(context.dateLocale);
    final dateLabel = dateFormat.format(note.date);

    // Look up the member if this note is associated with one
    final memberAsync = note.memberId != null
        ? ref.watch(activeMemberByIdProvider(note.memberId!))
        : null;
    final member = memberAsync?.value;

    Color? colorBar;
    if (note.colorHex != null) {
      try {
        colorBar = Color(int.parse(note.colorHex!.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }

    final displayTitle = redactSpoilers(
      note.title.isNotEmpty
          ? note.title
          : stripImageMarkdown(note.body.split('\n').first.trim()),
    );
    final isFallbackTitle = note.title.isEmpty;
    final titleLabel = displayTitle.isNotEmpty
        ? displayTitle
        : l10n.memberNoteUntitled;

    final semanticLabel = member != null
        ? '$titleLabel. ${l10n.memberSectionNotes}. ${member.name}. $dateLabel.'
        : '$titleLabel. ${l10n.memberSectionNotes}. $dateLabel.';

    return PrismSectionCard(
      semanticLabel: semanticLabel,
      accentColor: selected ? theme.colorScheme.primary : null,
      transitionDuration: Duration.zero,
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (colorBar != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(2),
                ),
                child: ColoredBox(
                  color: colorBar,
                  child: const SizedBox(width: 4),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: isFallbackTitle
                          ? FontWeight.normal
                          : FontWeight.w600,
                      fontStyle: isFallbackTitle
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (note.body.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: imagePreviewSpans(
                          redactSpoilers(note.body),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          iconColor: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dateLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      if (member != null) ...[
                        const SizedBox(width: 12),
                        MemberAvatar(
                          avatarImageData: member.avatarImageData,
                          memberName: member.name,
                          emoji: member.emoji,
                          customColorEnabled: member.customColorEnabled,
                          customColorHex: member.customColorHex,
                          size: 28,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
