import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/markdown/markdown_preview.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member.dart';
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
import 'package:prism_plurality/shared/widgets/member_chip.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/modal_side_sheet_marker.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
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
  bool _allowPopAfterInlineEditorDiscard = false;
  int _editorRevision = 0;

  // Search and filter state
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _searchQuery = '';
  bool _isSearchActive = false;
  Set<String> _filterMemberIds = const {};

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

  void _onClearMemberFilter(String memberId) {
    setState(() {
      _filterMemberIds = {
        for (final id in _filterMemberIds)
          if (id != memberId) id,
      };
    });
  }

  void _clearAllFilters() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _filterMemberIds = const {};
      _isSearchActive = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(allNotesProvider);
    final filterMembersAsync = ref.watch(userVisibleMemberListProvider);
    final filterMembers = filterMembersAsync.value ?? const [];
    final memberNameMap = ref.watch(memberNameMapProvider);
    final l10n = context.l10n;
    watchMemberSearchGroupSources(ref);
    final showFilterBar =
        _isSearchActive ||
        _searchQuery.trim().isNotEmpty ||
        _filterMemberIds.isNotEmpty;

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

    if (filterMembersAsync.hasValue && _filterMemberIds.isNotEmpty) {
      final visibleMemberIds = filterMembers.map((member) => member.id).toSet();
      final staleMemberIds = _filterMemberIds
          .where(
            (id) => id != filterNoMemberId && !visibleMemberIds.contains(id),
          )
          .toList(growable: false);
      if (staleMemberIds.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          PrismToast.show(context, message: l10n.memberNoteFilterMemberDeleted);
          setState(() {
            _filterMemberIds = {
              for (final id in _filterMemberIds)
                if (!staleMemberIds.contains(id)) id,
            };
          });
        });
      }
    }

    // Each pane owns its top bar so they sit side by side in two-pane mode:
    // the notes bar is scoped to the list pane, and the note detail fills its
    // whole pane (its own bar included).
    return PopScope(
      // The inline editor's guard is inactive, so route back must ask the
      // parent-owned controller before popping.
      canPop: _allowPopAfterInlineEditorDiscard || _editorPane == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_allowPopAfterInlineEditorDiscard) return;
        final shouldDiscard = await _confirmCloseInlineEditorIfNeeded();
        if (!shouldDiscard || !mounted) return;
        // Let the immediate follow-up pop pass before rebuild.
        setState(() {
          _allowPopAfterInlineEditorDiscard = true;
          _editorPane = null;
        });
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: ListDetailLayout(
        onClearSelection: () => unawaited(_clearDetailPane()),
        detail: (context) => _buildDetailPane(),
        list: (context, isWide) {
          setListDetailWide(isWide);
          return PrismPageScaffold(
            topBar: _NotesTopBar(
              title: l10n.memberSectionNotes,
              showBackButton: widget.showBackButton,
              searchActive: _isSearchActive || _searchQuery.trim().isNotEmpty,
              memberFilterActive: _filterMemberIds.isNotEmpty,
              onToggleSearch: () => setState(() {
                _isSearchActive = !_isSearchActive;
                if (!_isSearchActive) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              }),
              onOpenMemberFilter: () =>
                  _openMemberFilter(context, filterMembers),
              onCreateNote: () => unawaited(_openCreateNote(context)),
              filterBar: showFilterBar ? _buildFilterBar(l10n) : null,
            ),
            bodyPadding: EdgeInsets.zero,
            body: Column(
              children: [
                Expanded(
                  child: notesAsync.when(
                    loading: () => const PrismLoadingState(),
                    error: (_, _) => Center(child: Text(context.l10n.error)),
                    data: (notes) {
                      final hasActiveFilters =
                          _searchQuery.trim().length >= 2 ||
                          _filterMemberIds.isNotEmpty;
                      final filtered = filterNotes(
                        notes,
                        query: _searchQuery,
                        filterMemberIds: _filterMemberIds,
                        memberNameMap: memberNameMap,
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
                              memberNameMap: memberNameMap,
                              onTap: () =>
                                  unawaited(_openNote(context, note.id)),
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
      ),
    );
  }

  PreferredSizeWidget _buildFilterBar(AppLocalizations l10n) {
    final prefer = ref.watch(memberNamePreferDisplayProvider);
    final membersById = {
      for (final member
          in ref.watch(userVisibleMemberListProvider).value ?? const <Member>[])
        member.id: member,
    };
    final memberFilters = [
      for (final memberId in _filterMemberIds)
        if (memberId == filterNoMemberId)
          NotesMemberFilter(
            id: memberId,
            label: l10n.memberNoteFilterNoMember,
            avatar: Icon(AppIcons.removeCircleOutline, size: 20),
          )
        else if (membersById[memberId] case final member?)
          NotesMemberFilter(
            id: memberId,
            label: member.effectiveName(preferDisplayName: prefer),
            member: member,
          ),
    ];

    return NotesFilterBar(
      showSearch: _isSearchActive || _searchQuery.trim().isNotEmpty,
      searchController: _searchController,
      searchQuery: _searchQuery,
      autofocus: _isSearchActive && _searchQuery.isEmpty,
      onSearchChanged: _onSearchChanged,
      onClearSearch: _onClearSearch,
      onClearAllFilters: _clearAllFilters,
      memberFilters: memberFilters,
      onClearMemberFilter: _onClearMemberFilter,
    );
  }

  Future<void> _openMemberFilter(
    BuildContext context,
    List<Member> members,
  ) async {
    final terms = readTerminology(context, ref);

    final groups = members.isNotEmpty
        ? readMemberSearchGroups(ref, members)
        : <MemberSearchGroup>[];

    final result = await MemberSearchSheet.showMulti(
      context,
      members: members,
      termPlural: terms.plural,
      groups: groups,
      initialSelected: Set<String>.from(_filterMemberIds),
      allowEmptySelection: true,
      specialRows: [
        MemberSearchSpecialRow(
          rowKey: 'no_member',
          title: context.l10n.memberNoteFilterNoMember,
          leading: Icon(AppIcons.removeCircleOutline),
          multiSelectId: filterNoMemberId,
        ),
      ],
    );

    if (!mounted || result == null) return;
    setState(() => _filterMemberIds = Set<String>.from(result));
  }

  /// Wide-layout note detail/editor pane.
  Widget _buildDetailPane() {
    final editorPane = _editorPane;
    if (editorPane != null) {
      return NoteEditor(
        key: ValueKey('note-editor-${editorPane.revision}'),
        note: editorPane.note,
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
        _allowPopAfterInlineEditorDiscard = false;
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
        _allowPopAfterInlineEditorDiscard = false;
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
      _allowPopAfterInlineEditorDiscard = false;
      selectedDetailId = note.id;
      _editorPane = _NoteEditorPane.edit(
        note: note,
        revision: ++_editorRevision,
      );
    });
  }

  void _finishInlineEditor(Note note) {
    setState(() {
      _allowPopAfterInlineEditorDiscard = false;
      selectedDetailId = note.id;
      _editorPane = null;
    });
  }

  void _closeInlineEditor() {
    setState(() {
      _allowPopAfterInlineEditorDiscard = false;
      _editorPane = null;
    });
  }

  Future<void> _clearDetailPane() async {
    if (_editorPane != null) {
      final canCloseEditor = await _confirmCloseInlineEditorIfNeeded();
      if (!canCloseEditor || !mounted) return;
      setState(() {
        _allowPopAfterInlineEditorDiscard = false;
        _editorPane = null;
      });
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

class _NotesTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _NotesTopBar({
    required this.title,
    required this.showBackButton,
    required this.searchActive,
    required this.memberFilterActive,
    required this.onToggleSearch,
    required this.onOpenMemberFilter,
    required this.onCreateNote,
    this.filterBar,
  });

  final String title;
  final bool showBackButton;
  final bool searchActive;
  final bool memberFilterActive;
  final VoidCallback onToggleSearch;
  final VoidCallback onOpenMemberFilter;
  final VoidCallback onCreateNote;
  final PreferredSizeWidget? filterBar;

  @override
  Size get preferredSize => Size.fromHeight(
    PrismTokens.topBarHeight + (filterBar?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final activeTint = Theme.of(context).colorScheme.primary;
    final inModalSideSheet = ModalSideSheetMarker.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PrismTopBar(
          title: title,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showBackButton) ...[
                PrismTopBarAction(
                  icon: inModalSideSheet ? AppIcons.close : AppIcons.arrowBack,
                  tooltip: inModalSideSheet ? l10n.close : l10n.back,
                  onPressed: () => closeDetailSurface(context),
                ),
                const SizedBox(width: 8),
              ],
              PrismTopBarAction(
                icon: AppIcons.filterList,
                tooltip: l10n.memberNoteFilterByMember,
                tint: memberFilterActive ? activeTint : null,
                accentIcon: memberFilterActive,
                onPressed: onOpenMemberFilter,
              ),
              const SizedBox(width: 8),
              PrismTopBarAction(
                icon: AppIcons.search,
                tooltip: l10n.memberNoteSearchNotes,
                tint: searchActive ? activeTint : null,
                accentIcon: searchActive,
                onPressed: onToggleSearch,
              ),
            ],
          ),
          actions: [
            PrismTopBarAction(
              icon: AppIcons.add,
              tooltip: l10n.memberAddNoteTooltip,
              onPressed: onCreateNote,
            ),
          ],
        ),
        ?filterBar,
      ],
    );
  }
}

class _NoteEditorPane {
  const _NoteEditorPane._({required this.revision, this.note});

  factory _NoteEditorPane.create({required int revision}) =>
      _NoteEditorPane._(revision: revision);

  factory _NoteEditorPane.edit({required Note note, required int revision}) =>
      _NoteEditorPane._(revision: revision, note: note);

  final int revision;
  final Note? note;
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({
    required this.note,
    required this.selected,
    required this.memberNameMap,
    required this.onTap,
  });

  final Note note;
  final bool selected;
  final Map<String, String> memberNameMap;
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
    final prefer = ref.watch(memberNamePreferDisplayProvider);

    Color? colorBar;
    if (note.colorHex != null) {
      try {
        colorBar = Color(int.parse(note.colorHex!.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }

    final displayTitle = redactSpoilers(
      note.title.isNotEmpty
          ? note.title
          : stripPreviewMarkdown(
              note.body.split('\n').first.trim(),
              memberNameMap: memberNameMap,
            ),
    );
    final isFallbackTitle = note.title.isEmpty;
    final titleLabel = displayTitle.isNotEmpty
        ? displayTitle
        : l10n.memberNoteUntitled;

    final semanticLabel = member != null
        ? '$titleLabel. ${l10n.memberSectionNotes}. '
              '${member.effectiveName(preferDisplayName: prefer)}. $dateLabel.'
        : '$titleLabel. ${l10n.memberSectionNotes}. $dateLabel.';

    return PrismSectionCard(
      semanticLabel: semanticLabel,
      accentColor: selected ? theme.colorScheme.primary : null,
      transitionDuration: Duration.zero,
      onTap: onTap,
      child: Stack(
        children: [
          if (colorBar != null)
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(2),
                ),
                child: ColoredBox(
                  color: colorBar,
                  child: const SizedBox(width: 4),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(
              left: colorBar != null ? 16 : 0,
              top: 2,
              bottom: 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 14,
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
                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(
                      children: imagePreviewSpans(
                        redactSpoilers(note.body),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        iconColor: theme.colorScheme.onSurfaceVariant,
                        memberNameMap: memberNameMap,
                      ),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        dateLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                    if (member != null) ...[
                      const SizedBox(width: 12),
                      MemberChip(
                        member: member,
                        resolvedName: member.effectiveName(
                          preferDisplayName: prefer,
                        ),
                        style: MemberChipStyle.inline,
                        avatarSize: 20,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
