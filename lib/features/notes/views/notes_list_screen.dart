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
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/notes/providers/pending_note_selection_provider.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/notes/utils/notes_filter.dart';
import 'package:prism_plurality/features/notes/widgets/notes_filter_bar.dart';
import 'package:prism_plurality/features/members/widgets/note_editor.dart';
import 'package:prism_plurality/features/members/widgets/note_sheet.dart';
import 'package:prism_plurality/shared/markdown/spoiler_syntax.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/features/members/views/note_detail_screen.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/list_detail_layout.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
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

  // Search and filter state
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _searchQuery = '';
  bool _isSearchActive = false;
  String? _filterMemberId;

  String _notePath(String id) => switch (widget.branch) {
    NotesListBranch.settings => AppRoutePaths.settingsNote(id),
    NotesListBranch.notes => AppRoutePaths.note(id),
  };

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchControllerChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchControllerChanged);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchControllerChanged() {
    setState(() {});
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _searchQuery = value);
    });
  }

  void _onClearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _onClearMemberFilter() {
    setState(() => _filterMemberId = null);
  }

  void _clearAllFilters() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _filterMemberId = null;
      _isSearchActive = false;
    });
  }

  String? _effectiveMemberIdForCreate() {
    if (_filterMemberId == null) return null;
    if (_filterMemberId == filterNoMemberId) return null;
    return _filterMemberId;
  }

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

    // Monitor for deleted filter member
    if (_filterMemberId != null && _filterMemberId != filterNoMemberId) {
      final memberAsync = ref.watch(activeMemberByIdProvider(_filterMemberId!));
      if (memberAsync is AsyncData && memberAsync.value == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _filterMemberId == null) return;
          PrismToast.show(
            context,
            message: l10n.memberNoteFilterMemberDeleted,
          );
          _onClearMemberFilter();
        });
      }
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
                icon: AppIcons.search,
                tooltip: l10n.memberNoteSearchNotes,
                onPressed: () => setState(() {
                  _isSearchActive = !_isSearchActive;
                  if (!_isSearchActive) {
                    _searchController.clear();
                    _searchQuery = '';
                  }
                }),
              ),
              PrismTopBarAction(
                icon: AppIcons.filterList,
                tooltip: l10n.memberNoteFilterByMember,
                onPressed: () => _openMemberFilter(context),
              ),
              PrismTopBarAction(
                icon: AppIcons.add,
                tooltip: l10n.memberAddNoteTooltip,
                onPressed: () => unawaited(_openCreateNote(context)),
              ),
            ],
          ),
          bodyPadding: EdgeInsets.zero,
          body: Column(
            children: [
              if (_isSearchActive || _searchQuery.trim().isNotEmpty || _filterMemberId != null)
                _buildFilterBar(l10n),
              Expanded(
                child: notesAsync.when(
                  loading: () => const PrismLoadingState(),
                  error: (_, _) => Center(child: Text(context.l10n.error)),
                  data: (notes) {
                    final hasActiveFilters = _searchQuery.trim().length >= 2 ||
                        _filterMemberId != null;
                    final filtered = filterNotes(
                      notes,
                      query: _searchQuery,
                      filterMemberId: _filterMemberId,
                    );

                    if (notes.isEmpty) {
                      return EmptyState(
                        icon: Icon(AppIcons.noteOutlined),
                        title: l10n.memberNoteNoNotesYet,
                        subtitle: l10n.memberNoteEmptySubtitle,
                        actionLabel: l10n.memberNoteTitle,
                        onAction: () => unawaited(_openCreateNote(context)),
                      );
                    }

                    if (filtered.isEmpty && hasActiveFilters) {
                      return EmptyState(
                        icon: Icon(AppIcons.searchOff),
                        title: l10n.memberNoteNoFilteredNotes,
                        subtitle: l10n.memberNoteNoFilteredNotesSubtitle,
                        actionLabel: l10n.memberNoteClearFilters,
                        onAction: _clearAllFilters,
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
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final note = filtered[index];
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
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterBar(AppLocalizations l10n) {
    Widget? filterMemberAvatar;
    String? filterMemberName;

    if (_filterMemberId != null && _filterMemberId != filterNoMemberId) {
      final memberAsync = ref.watch(activeMemberByIdProvider(_filterMemberId!));
      final member = memberAsync.value;
      if (member != null) {
        filterMemberName = member.name;
        filterMemberAvatar = MemberAvatar(
          memberName: member.name,
          emoji: member.emoji,
          avatarImageData: member.avatarImageData,
          customColorEnabled: member.customColorEnabled,
          customColorHex: member.customColorHex,
          size: 20,
        );
      }
    } else if (_filterMemberId == filterNoMemberId) {
      filterMemberName = l10n.memberNoteFilterNoMember;
    }

    return NotesFilterBar(
      searchController: _searchController,
      searchQuery: _searchQuery,
      autofocus: _isSearchActive && _searchQuery.isEmpty,
      onSearchChanged: _onSearchChanged,
      onClearSearch: _onClearSearch,
      onClearAllFilters: _clearAllFilters,
      filterMemberId: _filterMemberId,
      filterMemberName: filterMemberName,
      filterMemberAvatar: filterMemberAvatar,
      onClearMemberFilter: _onClearMemberFilter,
    );
  }

  Future<void> _openMemberFilter(BuildContext context) async {
    final membersAsync = ref.read(activeMemberListProvider);
    final members = membersAsync.value ?? const [];
    final terms = readTerminology(context, ref);

    final groups = members.isNotEmpty
        ? readMemberSearchGroups(ref, members)
        : <MemberSearchGroup>[];

    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: terms.plural,
      groups: groups,
      specialRows: [
        MemberSearchSpecialRow(
          rowKey: 'no_member',
          title: context.l10n.memberNoteFilterNoMember,
          leading: Icon(AppIcons.removeCircleOutline),
          result: const MemberSearchResultCleared(),
        ),
      ],
    );

    if (!mounted) return;

    switch (result) {
      case MemberSearchResultSelected(:final memberId):
        setState(() => _filterMemberId = memberId);
      case MemberSearchResultCleared():
        setState(() => _filterMemberId = filterNoMemberId);
      case MemberSearchResultDismissed():
      case MemberSearchResultUnknown():
        break;
    }
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
    final effectiveMemberId = _effectiveMemberIdForCreate();
    if (isDetailPaneVisible) {
      final canCloseEditor = await _confirmCloseInlineEditorIfNeeded();
      if (!canCloseEditor || !mounted) return;

      setState(() {
        selectedDetailId = null;
        _editorPane = _NoteEditorPane.create(
          revision: ++_editorRevision,
          memberId: effectiveMemberId,
        );
      });
      return;
    }

    unawaited(
      PrismSheet.showFullScreen(
        context: context,
        builder: (context, scrollController) => NoteSheet(
          memberId: effectiveMemberId,
          scrollController: scrollController,
        ),
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
