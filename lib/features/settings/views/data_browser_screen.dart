import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_expandable_section.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';

/// Raw data inspector for browsing database records.
///
/// Provides a tabbed view of all major tables (Members, Sessions,
/// Conversations, Messages, Polls) with expandable rows showing
/// all fields as key-value pairs.
class DataBrowserScreen extends ConsumerStatefulWidget {
  const DataBrowserScreen({super.key});

  @override
  ConsumerState<DataBrowserScreen> createState() => _DataBrowserScreenState();
}

enum _DataTable { members, sessions, conversations, messages, polls }

class _DataBrowserScreenState extends ConsumerState<DataBrowserScreen> {
  _DataTable _selectedTable = _DataTable.members;
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.settingsDataBrowserTitle,
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.refresh,
            tooltip: context.l10n.settingsDataBrowserReloadTooltip,
            onPressed: () => setState(() => _refreshKey++),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          // Table selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: PrismSegmentedControl<_DataTable>(
              segments: [
                PrismSegment(value: _DataTable.members, label: context.l10n.settingsDataBrowserTabMembers),
                PrismSegment(
                  value: _DataTable.sessions,
                  label: context.l10n.settingsDataBrowserTabSessions,
                ),
                PrismSegment(
                  value: _DataTable.conversations,
                  label: context.l10n.settingsDataBrowserTabChats,
                ),
                PrismSegment(value: _DataTable.messages, label: context.l10n.settingsDataBrowserTabMessages),
                PrismSegment(value: _DataTable.polls, label: context.l10n.settingsDataBrowserTabPolls),
              ],
              selected: _selectedTable,
              onChanged: (value) {
                setState(() => _selectedTable = value);
              },
            ),
          ),

          // Data list — keyed by _refreshKey to force reload on refresh tap
          Expanded(
            child: switch (_selectedTable) {
              _DataTable.members => _MembersTable(key: ValueKey(_refreshKey)),
              _DataTable.sessions => _SessionsTable(key: ValueKey(_refreshKey)),
              _DataTable.conversations => _ConversationsTable(
                key: ValueKey(_refreshKey),
              ),
              _DataTable.messages => _MessagesTable(key: ValueKey(_refreshKey)),
              _DataTable.polls => _PollsTable(key: ValueKey(_refreshKey)),
            },
          ),
        ],
      ),
    );
  }
}

// -- Members Table ---------------------------------------------------------

class _MembersTable extends ConsumerStatefulWidget {
  const _MembersTable({super.key});

  @override
  ConsumerState<_MembersTable> createState() => _MembersTableState();
}

class _MembersTableState extends ConsumerState<_MembersTable> {
  List<Member>? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(memberRepositoryProvider);
      final data = await repo.getAllMembers();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(context.l10n.settingsDataBrowserError(_error.toString())));
    final data = _data;
    if (data == null) return const PrismLoadingState();
    if (data.isEmpty) return Center(child: Text(context.l10n.settingsDataBrowserNoMembers));
    return ListView.builder(
      itemCount: data.length,
      itemBuilder: (context, index) {
        final m = data[index];
        return _ExpandableRecord(
          primaryField: m.name,
          secondaryField: m.pronouns ?? '',
          id: m.id,
          fields: {
            'id': m.id,
            'name': m.name,
            'pronouns': m.pronouns ?? '',
            'emoji': m.emoji,
            'age': m.age?.toString() ?? 'null',
            'bio': m.bio ?? '',
            'isActive': m.isActive.toString(),
            'isAdmin': m.isAdmin.toString(),
            'displayOrder': m.displayOrder.toString(),
            'customColorEnabled': m.customColorEnabled.toString(),
            'customColorHex': m.customColorHex ?? 'null',
            'createdAt': m.createdAt.toIso8601String(),
            'hasAvatar': (m.avatarImageData != null).toString(),
          },
        );
      },
    );
  }
}

// -- Sessions Table --------------------------------------------------------

class _SessionsTable extends ConsumerStatefulWidget {
  const _SessionsTable({super.key});

  @override
  ConsumerState<_SessionsTable> createState() => _SessionsTableState();
}

class _SessionsTableState extends ConsumerState<_SessionsTable> {
  List<FrontingSession>? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(frontingSessionRepositoryProvider);
      final data = await repo.getAllSessions();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(context.l10n.settingsDataBrowserError(_error.toString())));
    final data = _data;
    if (data == null) return const PrismLoadingState();
    if (data.isEmpty) return Center(child: Text(context.l10n.settingsDataBrowserNoSessions));
    return ListView.builder(
      itemCount: data.length,
      itemBuilder: (context, index) {
        final s = data[index];
        return _ExpandableRecord(
          primaryField: s.startTime.toIso8601String().substring(0, 16),
          secondaryField: s.isActive ? context.l10n.settingsDataBrowserSessionActive : context.l10n.settingsDataBrowserSessionEnded,
          id: s.id,
          fields: {
            'id': s.id,
            'startTime': s.startTime.toIso8601String(),
            'endTime': s.endTime?.toIso8601String() ?? context.l10n.settingsDataBrowserSessionEndTimeActive,
            'memberId': s.memberId ?? 'null',
            'coFronterIds': s.coFronterIds.join(', '),
            'notes': s.notes ?? '',
            'confidence': s.confidence?.name ?? 'null',
            'isActive': s.isActive.toString(),
            'duration': s.duration.toString(),
          },
        );
      },
    );
  }
}

// -- Conversations Table ---------------------------------------------------

class _ConversationsTable extends ConsumerStatefulWidget {
  const _ConversationsTable({super.key});

  @override
  ConsumerState<_ConversationsTable> createState() =>
      _ConversationsTableState();
}

class _ConversationsTableState extends ConsumerState<_ConversationsTable> {
  List<Conversation>? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(conversationRepositoryProvider);
      final data = await repo.getAllConversations();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(context.l10n.settingsDataBrowserError(_error.toString())));
    final data = _data;
    if (data == null) return const PrismLoadingState();
    if (data.isEmpty) return Center(child: Text(context.l10n.settingsDataBrowserNoConversations));
    return ListView.builder(
      itemCount: data.length,
      itemBuilder: (context, index) {
        final c = data[index];
        return _ExpandableRecord(
          primaryField: c.title ?? context.l10n.settingsDataBrowserUntitled,
          secondaryField: context.l10n.settingsDataBrowserParticipantCount(c.participantIds.length),
          id: c.id,
          fields: {
            'id': c.id,
            'title': c.title ?? 'null',
            'emoji': c.emoji ?? 'null',
            'isDirectMessage': c.isDirectMessage.toString(),
            'creatorId': c.creatorId ?? 'null',
            'participantIds': c.participantIds.join(', '),
            'createdAt': c.createdAt.toIso8601String(),
            'lastActivityAt': c.lastActivityAt.toIso8601String(),
          },
        );
      },
    );
  }
}

// -- Messages Table --------------------------------------------------------

class _MessagesTable extends ConsumerStatefulWidget {
  const _MessagesTable({super.key});

  @override
  ConsumerState<_MessagesTable> createState() => _MessagesTableState();
}

class _MessagesTableState extends ConsumerState<_MessagesTable> {
  List<Conversation>? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final convRepo = ref.read(conversationRepositoryProvider);
      final data = await convRepo.getAllConversations();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(context.l10n.settingsDataBrowserError(_error.toString())));
    final data = _data;
    if (data == null) return const PrismLoadingState();
    if (data.isEmpty) return Center(child: Text(context.l10n.settingsDataBrowserNoMessages));
    final msgRepo = ref.read(chatMessageRepositoryProvider);
    return ListView.builder(
      itemCount: data.length,
      itemBuilder: (context, index) {
        final conv = data[index];
        return _MessagesForConversation(
          conversation: conv,
          messageRepo: msgRepo,
        );
      },
    );
  }
}

class _MessagesForConversation extends StatefulWidget {
  const _MessagesForConversation({
    required this.conversation,
    required this.messageRepo,
  });

  final Conversation conversation;
  final dynamic messageRepo;

  @override
  State<_MessagesForConversation> createState() =>
      _MessagesForConversationState();
}

class _MessagesForConversationState extends State<_MessagesForConversation> {
  List<ChatMessage>? _messages;
  Object? _error;
  bool _loading = false;

  Future<void> _loadMessages() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await widget.messageRepo.getMessagesForConversation(
        widget.conversation.id,
      );
      if (mounted) setState(() => _messages = messages);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messages = _messages;
    final contentChildren = _loading
        ? const [
            Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: PrismLoadingState()),
            ),
          ]
        : messages == null
        ? const [SizedBox.shrink()]
        : messages.isEmpty
        ? [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
              child: Text(
                context.l10n.settingsDataBrowserNoMessagesInConversation,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ]
        : messages.map((msg) {
            return _ExpandableRecord(
              primaryField: msg.content.length > 50
                  ? '${msg.content.substring(0, 50)}...'
                  : msg.content,
              secondaryField: msg.isSystemMessage ? context.l10n.settingsDataBrowserSystemMessage : '',
              id: msg.id,
              margin: EdgeInsets.zero,
              fields: {
                'id': msg.id,
                'content': msg.content,
                'timestamp': msg.timestamp.toIso8601String(),
                'authorId': msg.authorId ?? 'null',
                'conversationId': msg.conversationId,
                'isSystemMessage': msg.isSystemMessage.toString(),
                'editedAt': msg.editedAt?.toIso8601String() ?? 'null',
                'reactions': msg.reactions.length.toString(),
              },
            );
          }).toList();

    final String subtitle;
    if (_error != null) {
      subtitle = context.l10n.settingsDataBrowserLoadError;
    } else if (messages != null) {
      subtitle = context.l10n.settingsDataBrowserMessageCount(messages.length);
    } else {
      subtitle = context.l10n.settingsDataBrowserTapToLoad;
    }

    return PrismExpandableSection(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      onExpansionChanged: (expanded) {
        // Load on first expand, or retry on expand after error
        if (expanded && (messages == null || _error != null)) {
          _loadMessages();
        }
      },
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        radius: 16,
        child: Text(
          widget.conversation.emoji ?? '💬',
          style: const TextStyle(fontSize: 14),
        ),
      ),
      title: Text(
        widget.conversation.title ?? context.l10n.settingsDataBrowserUntitled,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: _error != null
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      contentSpacing: 8,
      children: contentChildren,
    );
  }
}

// -- Polls Table -----------------------------------------------------------

class _PollsTable extends ConsumerStatefulWidget {
  const _PollsTable({super.key});

  @override
  ConsumerState<_PollsTable> createState() => _PollsTableState();
}

class _PollsTableState extends ConsumerState<_PollsTable> {
  List<Poll>? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(pollRepositoryProvider);
      final data = await repo.getAllPolls();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(context.l10n.settingsDataBrowserError(_error.toString())));
    final data = _data;
    if (data == null) return const PrismLoadingState();
    if (data.isEmpty) return Center(child: Text(context.l10n.settingsDataBrowserNoPolls));
    return ListView.builder(
      itemCount: data.length,
      itemBuilder: (context, index) {
        final p = data[index];
        return _ExpandableRecord(
          primaryField: p.question,
          secondaryField: p.isClosed ? context.l10n.settingsDataBrowserPollClosed : context.l10n.settingsDataBrowserPollActive,
          id: p.id,
          fields: {
            'id': p.id,
            'question': p.question,
            'isAnonymous': p.isAnonymous.toString(),
            'allowsMultipleVotes': p.allowsMultipleVotes.toString(),
            'isClosed': p.isClosed.toString(),
            'expiresAt': p.expiresAt?.toIso8601String() ?? 'null',
            'createdAt': p.createdAt.toIso8601String(),
            'optionCount': p.options.length.toString(),
          },
        );
      },
    );
  }
}

// -- Expandable Record Widget ----------------------------------------------

class _ExpandableRecord extends StatelessWidget {
  const _ExpandableRecord({
    required this.primaryField,
    required this.secondaryField,
    required this.id,
    required this.fields,
    this.margin = const EdgeInsets.fromLTRB(16, 4, 16, 4),
  });

  final String primaryField;
  final String secondaryField;
  final String id;
  final Map<String, String> fields;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final truncatedId = id.length > 8 ? '${id.substring(0, 8)}...' : id;

    return PrismExpandableSection(
      margin: margin,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        radius: 16,
        child: Icon(
          AppIcons.dataObject,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        primaryField,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Text(
            truncatedId,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (secondaryField.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              secondaryField,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: fields.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(
                          entry.key,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          entry.value,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
