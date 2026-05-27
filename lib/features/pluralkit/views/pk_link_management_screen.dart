import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/daos/pk_mapping_state_dao.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/utils/pk_link_utils.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Snapshot of locals + PK fetch the management screen renders against.
///
/// Lives on the screen-scoped controller (`pkLinkManagementControllerProvider`)
/// so the screen can refresh without invalidating unrelated PK providers. When
/// the user is connected to PK, [pkMembers] reflects the most recent fetch;
/// when offline the screen renders with an empty fetch and the Unresolved
/// section is hidden per the plan's edge cases.
class PkLinkManagementState {
  const PkLinkManagementState({
    required this.localMembers,
    required this.pkMembers,
    required this.isConnected,
    required this.fetchedPkUuids,
    required this.fetchedPkIds,
    required this.pkMembersByUuid,
    required this.pkMembersById,
    this.fetchError,
  });

  final List<domain.Member> localMembers;
  final List<PKMember> pkMembers;

  /// True when there's an active PluralKit token. Hides Unresolved and
  /// disables Link actions when false.
  final bool isConnected;

  /// Non-null when a fetch attempt failed while the token was still active.
  /// Distinct from [isConnected] so the screen can keep Refresh enabled
  /// (and show a "couldn't load" hint) instead of collapsing transient
  /// network failures into the disabled-offline state.
  final Object? fetchError;

  /// True iff PK is paired AND the most recent fetch succeeded. Disables
  /// actions like row-level Link and Add Link that need a fresh PK roster.
  bool get hasFreshFetch => isConnected && fetchError == null;

  final Set<String> fetchedPkUuids;
  final Set<String> fetchedPkIds;

  /// PK members keyed by UUID for quick lookups when rendering Synced /
  /// Excluded rows.
  final Map<String, PKMember> pkMembersByUuid;

  /// PK members keyed by 5-char short ID. Same purpose as [pkMembersByUuid]
  /// but for locals that only carry `pluralkit_id`.
  final Map<String, PKMember> pkMembersById;

  /// Locals whose PK fields resolve in the current fetch AND
  /// `pluralkit_sync_ignored = false`. Rendered in the Synced section.
  ///
  /// Excluded members are filtered out — they're rendered in the Excluded
  /// section instead even if their fields would otherwise resolve.
  ///
  /// Offline fallback: when [isConnected] is false the fetched sets are
  /// empty and `hasResolvablePluralKitLink` would always return false.
  /// Per the plan's Part 2 edge cases, the Synced section still renders
  /// (with "Linked (offline)" captions) so the user can see the link
  /// state they had before disconnecting. Bucket on `hasPluralKitLink`
  /// alone in that case.
  List<domain.Member> get syncedMembers => [
        for (final m in localMembers)
          if (!m.pluralkitSyncIgnored &&
              (isConnected
                  ? hasResolvablePluralKitLink(
                      m,
                      fetchedPkUuids: fetchedPkUuids,
                      fetchedPkIds: fetchedPkIds,
                    )
                  : hasPluralKitLink(m)))
            m,
      ];

  /// Locals where the user excluded sync. Includes members with or without
  /// resolved/unresolved PK fields — the row subtitle calls it out.
  List<domain.Member> get excludedMembers => [
        for (final m in localMembers)
          if (m.pluralkitSyncIgnored) m,
      ];

  /// Locals with PK fields set, NOT resolved in the current fetch, and not
  /// excluded. Hidden when offline (we cannot tell whether they resolve).
  List<domain.Member> get unresolvedMembers => [
        for (final m in localMembers)
          if (!m.pluralkitSyncIgnored &&
              hasPluralKitLink(m) &&
              !hasResolvablePluralKitLink(
                m,
                fetchedPkUuids: fetchedPkUuids,
                fetchedPkIds: fetchedPkIds,
              ))
            m,
      ];

  /// PK members not currently linked to any non-excluded local. Used as the
  /// search corpus for both the row-level Link action and the top-level
  /// "Add link to existing member" → second sheet.
  List<PKMember> get unmappedPkMembers {
    final consumedUuids = <String>{};
    final consumedIds = <String>{};
    for (final m in localMembers) {
      if (m.pluralkitSyncIgnored) continue;
      final uuid = m.pluralkitUuid?.trim();
      if (uuid != null && uuid.isNotEmpty) consumedUuids.add(uuid);
      final id = m.pluralkitId?.trim();
      if (id != null && id.isNotEmpty) consumedIds.add(id);
    }
    return [
      for (final pk in pkMembers)
        if (!consumedUuids.contains(pk.uuid) && !consumedIds.contains(pk.id))
          pk,
    ];
  }
}

/// Screen-scoped controller for the Manage PluralKit links screen.
///
/// Owns the locals + PK fetch snapshot and exposes a [refresh] hook so users
/// can re-fetch without invalidating the global PK sync provider.
class PkLinkManagementController
    extends AsyncNotifier<PkLinkManagementState> {
  @override
  Future<PkLinkManagementState> build() async {
    return _load();
  }

  Future<PkLinkManagementState> _load() async {
    final memberRepo = ref.read(memberRepositoryProvider);
    final allLocals = await memberRepo.getAllMembers();
    final syncState = ref.read(pluralKitSyncProvider);

    if (!syncState.isConnected) {
      return PkLinkManagementState(
        localMembers: allLocals,
        pkMembers: const [],
        isConnected: false,
        fetchedPkUuids: const {},
        fetchedPkIds: const {},
        pkMembersByUuid: const {},
        pkMembersById: const {},
      );
    }

    final syncService = ref.read(pluralKitSyncServiceProvider);
    List<PKMember> pkMembers = const [];
    try {
      final (_, fetched) = await syncService.fetchPkMembersWithoutImport();
      pkMembers = fetched;
    } catch (error) {
      // Network failure on a still-connected account. Surface the error
      // via [fetchError] so the screen can keep Refresh enabled for retry
      // and show a hint, instead of collapsing into the disabled-offline
      // state (which the previous draft did, leaving the user with no
      // way to recover from a transient failure).
      //
      // Synced + Excluded sections still render (Synced falls back to the
      // hasPluralKitLink bucketing via `isConnected: false` semantics);
      // Unresolved hides because we cannot tell which fields resolve.
      return PkLinkManagementState(
        localMembers: allLocals,
        pkMembers: const [],
        isConnected: false,
        fetchedPkUuids: const {},
        fetchedPkIds: const {},
        pkMembersByUuid: const {},
        pkMembersById: const {},
        fetchError: error,
      );
    }

    final fetchedPkUuids = {for (final pk in pkMembers) pk.uuid};
    final fetchedPkIds = {for (final pk in pkMembers) pk.id};
    final pkMembersByUuid = {for (final pk in pkMembers) pk.uuid: pk};
    final pkMembersById = {for (final pk in pkMembers) pk.id: pk};

    return PkLinkManagementState(
      localMembers: allLocals,
      pkMembers: pkMembers,
      isConnected: true,
      fetchedPkUuids: fetchedPkUuids,
      fetchedPkIds: fetchedPkIds,
      pkMembersByUuid: pkMembersByUuid,
      pkMembersById: pkMembersById,
    );
  }

  /// Re-run [_load], surfacing the loading spinner during the fetch.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }
}

final pkLinkManagementControllerProvider =
    AsyncNotifierProvider<PkLinkManagementController, PkLinkManagementState>(
  PkLinkManagementController.new,
);

/// Steady-state surface for managing per-member PK link state.
///
/// Three sections (Synced / Excluded / Unresolved) bucket every local by the
/// state described in the plan's Part 2. Top-of-screen actions cover
/// "Refresh from PluralKit" and "Add link to existing member"; the latter
/// opens a search over all locals → second search over unmapped PK members.
///
/// Reachable from [`PluralKitSetupScreen`] via "Manage member links."
class PkLinkManagementScreen extends ConsumerWidget {
  const PkLinkManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pkLinkManagementControllerProvider);
    final l10n = context.l10n;

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: l10n.pkLinkManagementTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: async.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                PrismButton(
                  onPressed: () => ref
                      .read(pkLinkManagementControllerProvider.notifier)
                      .refresh(),
                  icon: AppIcons.sync,
                  label: l10n.pkLinkManagementRefresh,
                  tone: PrismButtonTone.filled,
                ),
              ],
            ),
          ),
        ),
        data: (state) => _ManagementBody(state: state),
      ),
    );
  }
}

class _ManagementBody extends ConsumerWidget {
  const _ManagementBody({required this.state});
  final PkLinkManagementState state;

  /// Opens the row-level Link search: pick a PK member to link this local
  /// to. Routes through the applier so the same write path used by the
  /// mapping screen is reused (which uses `applyPluralKitLink` and resumes
  /// sync). Disabled when offline.
  Future<void> _showRowLinkSearch(
    BuildContext context,
    WidgetRef ref,
    domain.Member local,
  ) async {
    final l10n = context.l10n;
    final unmapped = state.unmappedPkMembers;
    if (unmapped.isEmpty) {
      PrismToast.show(
        context,
        message: l10n.pkMappingRowNoCandidatesCaption,
      );
      return;
    }

    final pkPicked = await _pickPkMember(
      context: context,
      candidates: unmapped,
      title: l10n.pkLinkManagementLinkAction,
    );
    if (!context.mounted || pkPicked == null) return;
    await _applyLink(context, ref, local: local, pkMember: pkPicked);
  }

  /// Opens the top-level "Add link to existing member" flow: search all
  /// locals → second sheet with the unmapped PK members. Selecting a PK
  /// member routes through `applyPluralKitLink` (resumes sync for excluded,
  /// overwrites stale PK fields for unresolved).
  Future<void> _showAddLinkFlow(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final unmapped = state.unmappedPkMembers;
    if (unmapped.isEmpty) {
      PrismToast.show(
        context,
        message: l10n.pkMappingRowNoCandidatesCaption,
      );
      return;
    }

    final localId = await _pickLocalMember(
      context: context,
      locals: state.localMembers,
      title: l10n.pkLinkManagementAddLinkAction,
      state: state,
    );
    if (!context.mounted || localId == null) return;

    final local = state.localMembers.firstWhere(
      (m) => m.id == localId,
      orElse: () => state.localMembers.first,
    );

    final pkPicked = await _pickPkMember(
      context: context,
      candidates: unmapped,
      title: l10n.pkLinkManagementLinkAction,
    );
    if (!context.mounted || pkPicked == null) return;

    await _applyLink(context, ref, local: local, pkMember: pkPicked);
  }

  /// Runs a `PkLinkDecision` through the applier so the PR 1.7 path
  /// (`applyPluralKitLink` + post-link metadata pull) is used. The applier
  /// owns network calls, snapshot semantics, and event bus emissions.
  Future<void> _applyLink(
    BuildContext context,
    WidgetRef ref, {
    required domain.Member local,
    required PKMember pkMember,
  }) async {
    final l10n = context.l10n;
    final syncService = ref.read(pluralKitSyncServiceProvider);
    final client = await syncService.buildClientIgnoringMappingGate();
    if (!context.mounted) {
      client?.dispose();
      return;
    }
    if (client == null) {
      PrismToast.error(
        context,
        message: l10n.pkLinkManagementOfflineCaption,
      );
      return;
    }

    try {
      final memberRepo = ref.read(memberRepositoryProvider);
      final db = ref.read(databaseProvider);
      final bus = ref.read(pkSyncEventBusProvider);
      final applier = PkMappingApplier(
        members: memberRepo,
        state: PkMappingStateDao(db),
        pushService: const PkPushService(),
        client: client,
        bus: bus,
      );
      final resolution = PkResolutionSnapshot(
        fetchedPkUuids: state.fetchedPkUuids,
        fetchedPkIds: state.fetchedPkIds,
      );
      final results = await applier.apply(
        [PkLinkDecision(localMemberId: local.id, pkMember: pkMember)],
        resolution: resolution,
      );
      if (!context.mounted) return;
      final failure = results.firstWhere(
        (r) => r.outcome == PkApplyOutcome.failed,
        orElse: () => results.first,
      );
      if (failure.outcome == PkApplyOutcome.failed) {
        // Don't surface failure.error raw — it's an English StateError
        // message from the applier (e.g. "PluralKit member X is already
        // linked to Y"). Localize via a generic "couldn't link" message
        // and log the raw cause for diagnosis. A proper typed-exception
        // hierarchy with per-failure-reason l10n keys is a future polish.
        if (failure.error != null) {
          debugPrint(
            '[PK_LINK_MGMT] Link decision failed: ${failure.error}',
          );
        }
        PrismToast.error(
          context,
          message: l10n.pkLinkManagementLinkFailed(
            pkMember.displayName ?? pkMember.name,
          ),
        );
        return;
      }
      PrismToast.success(
        context,
        message: l10n.pkLinkManagementMemberStateLinked(
          pkMember.displayName ?? pkMember.name,
        ),
      );
    } finally {
      client.dispose();
    }

    await ref.read(pkLinkManagementControllerProvider.notifier).refresh();
  }

  Future<void> _exclude(
    BuildContext context,
    WidgetRef ref,
    domain.Member local,
  ) async {
    await ref.read(memberRepositoryProvider).excludePluralKitSync(local.id);
    await ref.read(pkLinkManagementControllerProvider.notifier).refresh();
  }

  Future<void> _resume(
    BuildContext context,
    WidgetRef ref,
    domain.Member local,
  ) async {
    await ref.read(memberRepositoryProvider).resumePluralKitSync(local.id);
    await ref.read(pkLinkManagementControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final synced = state.syncedMembers;
    final excluded = state.excludedMembers;
    // Hide Unresolved when offline — see plan's edge cases.
    final unresolved =
        state.isConnected ? state.unresolvedMembers : const <domain.Member>[];

    if (synced.isEmpty && excluded.isEmpty && unresolved.isEmpty) {
      return EmptyState(
        icon: Icon(AppIcons.people),
        title: l10n.pkMappingEmptyTitle,
        subtitle: l10n.pkLinkManagementEmptyCount,
      );
    }

    final hasFetchError = state.fetchError != null;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (!state.isConnected && !hasFetchError) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.pkLinkManagementOfflineCaption,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
        if (hasFetchError) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.pkLinkManagementFetchFailedCaption,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
        // Top-of-screen actions.
        PrismButton(
          onPressed: () => ref
              .read(pkLinkManagementControllerProvider.notifier)
              .refresh(),
          icon: AppIcons.sync,
          label: l10n.pkLinkManagementRefresh,
          tone: PrismButtonTone.outlined,
          expanded: true,
          // Stay enabled on fetch failures so the user can retry — only
          // disable when truly disconnected (no PK token).
          enabled: state.isConnected || hasFetchError,
        ),
        const SizedBox(height: 8),
        PrismButton(
          key: const ValueKey('pkLinkManagementAddLinkButton'),
          onPressed: () => _showAddLinkFlow(context, ref),
          icon: AppIcons.link,
          label: l10n.pkLinkManagementAddLinkAction,
          tone: PrismButtonTone.filled,
          expanded: true,
          enabled: state.hasFreshFetch && state.unmappedPkMembers.isNotEmpty,
        ),

        if (synced.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionHeader(title: l10n.pkLinkManagementSectionSynced),
          const SizedBox(height: 8),
          PrismSectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final m in synced)
                  _SyncedRow(
                    local: m,
                    pkMember: _pkMemberFor(m),
                    isConnected: state.isConnected,
                    onExclude: () => _exclude(context, ref, m),
                  ),
              ],
            ),
          ),
        ],

        if (excluded.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionHeader(title: l10n.pkLinkManagementSectionExcluded),
          const SizedBox(height: 8),
          PrismSectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final m in excluded)
                  _ExcludedRow(
                    local: m,
                    pkMember: _pkMemberFor(m),
                    isConnected: state.isConnected,
                    fetchedPkUuids: state.fetchedPkUuids,
                    fetchedPkIds: state.fetchedPkIds,
                    onResume: () => _resume(context, ref, m),
                  ),
              ],
            ),
          ),
        ],

        if (unresolved.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionHeader(title: l10n.pkLinkManagementSectionUnresolved),
          const SizedBox(height: 8),
          PrismSectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final m in unresolved)
                  _UnresolvedRow(
                    local: m,
                    onLink: state.isConnected
                        ? () => _showRowLinkSearch(context, ref, m)
                        : null,
                    onExclude: () => _exclude(context, ref, m),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  /// Resolve the PK member for a local that carries PK fields, preferring
  /// UUID over short ID. Returns null when the fields don't resolve in the
  /// current fetch (offline, unresolved, or stale).
  PKMember? _pkMemberFor(domain.Member local) {
    final uuid = local.pluralkitUuid?.trim();
    if (uuid != null && uuid.isNotEmpty) {
      final hit = state.pkMembersByUuid[uuid];
      if (hit != null) return hit;
    }
    final id = local.pluralkitId?.trim();
    if (id != null && id.isNotEmpty) {
      return state.pkMembersById[id];
    }
    return null;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SyncedRow extends StatelessWidget {
  const _SyncedRow({
    required this.local,
    required this.pkMember,
    required this.isConnected,
    required this.onExclude,
  });

  final domain.Member local;
  final PKMember? pkMember;
  final bool isConnected;
  final VoidCallback onExclude;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final pkName = pkMember?.displayName ?? pkMember?.name;
    final subtitleText = isConnected && pkName != null
        ? '${pkMember!.id} · $pkName'
        : l10n.pkLinkManagementOfflineRowCaption;
    return PrismListRow(
      key: ValueKey('pkLinkManagementSyncedRow-${local.id}'),
      leading: MemberAvatar(
        memberName: local.name,
        emoji: local.emoji,
        customColorEnabled: local.customColorEnabled,
        customColorHex: local.customColorHex,
        avatarImageData: local.avatarImageData,
        size: 36,
      ),
      title: Text(local.name),
      subtitle: Text(
        subtitleText,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: PrismButton(
        key: ValueKey('pkLinkManagementExcludeButton-${local.id}'),
        onPressed: onExclude,
        label: l10n.pkLinkManagementExclude,
        tone: PrismButtonTone.subtle,
      ),
    );
  }
}

class _ExcludedRow extends StatelessWidget {
  const _ExcludedRow({
    required this.local,
    required this.pkMember,
    required this.isConnected,
    required this.fetchedPkUuids,
    required this.fetchedPkIds,
    required this.onResume,
  });

  final domain.Member local;
  final PKMember? pkMember;
  final bool isConnected;
  final Set<String> fetchedPkUuids;
  final Set<String> fetchedPkIds;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    // Pick the subtitle to match the row's link state. The Excluded bucket
    // includes locals with any of the three states (linked, unresolved,
    // not linked), so the subtitle must reflect that.
    final hasLink = hasPluralKitLink(local);
    final resolves = isConnected &&
        hasResolvablePluralKitLink(
          local,
          fetchedPkUuids: fetchedPkUuids,
          fetchedPkIds: fetchedPkIds,
        );
    final String subtitleText;
    if (hasLink && resolves) {
      final pkName = pkMember?.displayName ?? pkMember?.name ?? '';
      subtitleText = l10n.pkLinkManagementMemberStateExcludedLinked(pkName);
    } else if (hasLink) {
      // Either offline (cannot tell) or fields don't resolve. Use the
      // "linked to <pkId>" copy with the stored short ID.
      final pkId = local.pluralkitId?.trim().isNotEmpty == true
          ? local.pluralkitId!.trim()
          : local.pluralkitUuid?.trim() ?? '';
      subtitleText = l10n.pkLinkManagementMemberStateUnresolved(pkId);
    } else {
      subtitleText = l10n.pkLinkManagementMemberStateExcludedUnlinked;
    }

    return PrismListRow(
      key: ValueKey('pkLinkManagementExcludedRow-${local.id}'),
      leading: MemberAvatar(
        memberName: local.name,
        emoji: local.emoji,
        customColorEnabled: local.customColorEnabled,
        customColorHex: local.customColorHex,
        avatarImageData: local.avatarImageData,
        size: 36,
      ),
      title: Text(local.name),
      subtitle: Text(
        subtitleText,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: PrismButton(
        key: ValueKey('pkLinkManagementResumeButton-${local.id}'),
        onPressed: onResume,
        label: l10n.pkLinkManagementResume,
        tone: PrismButtonTone.filled,
      ),
    );
  }
}

class _UnresolvedRow extends StatelessWidget {
  const _UnresolvedRow({
    required this.local,
    required this.onLink,
    required this.onExclude,
  });

  final domain.Member local;
  final VoidCallback? onLink;
  final VoidCallback onExclude;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final pkId = local.pluralkitId?.trim().isNotEmpty == true
        ? local.pluralkitId!.trim()
        : local.pluralkitUuid?.trim() ?? '';

    return PrismListRow(
      key: ValueKey('pkLinkManagementUnresolvedRow-${local.id}'),
      leading: MemberAvatar(
        memberName: local.name,
        emoji: local.emoji,
        customColorEnabled: local.customColorEnabled,
        customColorHex: local.customColorHex,
        avatarImageData: local.avatarImageData,
        size: 36,
      ),
      title: Text(local.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pkId.isEmpty
                ? l10n.pkLinkManagementUnresolvedCaption
                : l10n.pkLinkManagementMemberStateUnresolved(pkId),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            l10n.pkLinkManagementUnresolvedCaption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PrismButton(
                key: ValueKey(
                  'pkLinkManagementUnresolvedLinkButton-${local.id}',
                ),
                onPressed: onLink ?? () {},
                label: l10n.pkLinkManagementLinkAction,
                tone: PrismButtonTone.filled,
                enabled: onLink != null,
              ),
              PrismButton(
                key: ValueKey(
                  'pkLinkManagementUnresolvedExcludeButton-${local.id}',
                ),
                onPressed: onExclude,
                label: l10n.pkLinkManagementExclude,
                tone: PrismButtonTone.subtle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search sheet helpers
// ---------------------------------------------------------------------------

/// Opens [MemberSearchSheet.showSingle] with the supplied PK members rendered
/// as a synthetic local-member list. The sheet doesn't speak PK, so we map
/// each PK member into a placeholder `domain.Member` whose name/displayName
/// reflect the PK side. Returns the picked [PKMember] or null on dismiss.
Future<PKMember?> _pickPkMember({
  required BuildContext context,
  required List<PKMember> candidates,
  required String title,
}) async {
  // Build a stable id-keyed lookup so we can map the search sheet's String
  // result back to the original PK member without identity hashing.
  final byKey = <String, PKMember>{
    for (final pk in candidates) _pkSearchKey(pk): pk,
  };
  final synthetic = [
    for (final pk in candidates)
      domain.Member(
        id: _pkSearchKey(pk),
        name: pk.name,
        displayName: pk.displayName,
        emoji: '',
        createdAt: DateTime.now(),
        pluralkitUuid: pk.uuid,
        pluralkitId: pk.id,
      ),
  ];
  final result = await MemberSearchSheet.showSingle(
    context,
    members: synthetic,
    termPlural: context.l10n.settingsTerminologyOptionMembers,
    title: title,
  );
  if (result is MemberSearchResultSelected) {
    return byKey[result.memberId];
  }
  return null;
}

String _pkSearchKey(PKMember pk) => '__pk__${pk.uuid}';

/// Opens the "Add link to existing member" search sheet — a normal local
/// search but with each row's trailing slot showing the local's current PK
/// state so the user can see at a glance whether picking the row will resume
/// sync for an excluded member, overwrite stale fields on an unresolved
/// local, or link a Prism-only local for the first time.
Future<String?> _pickLocalMember({
  required BuildContext context,
  required List<domain.Member> locals,
  required String title,
  PkLinkManagementState? state,
}) async {
  final l10n = context.l10n;
  final result = await MemberSearchSheet.showSingle(
    context,
    members: locals,
    termPlural: l10n.settingsTerminologyOptionMembers,
    title: title,
    trailingBuilder: (m) {
      final label = pkLinkManagementSearchLabelFor(l10n, m, state: state);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    },
  );
  if (result is MemberSearchResultSelected) {
    return result.memberId;
  }
  return null;
}

/// Returns the same per-local state label the "Add link to existing member"
/// flow renders in the trailing slot of each row. Exposed so the screen's
/// widget tests can assert that each local's label matches the expected
/// localized string without driving the real sheet.
///
/// When [state] is supplied, link rendering uses the live PK fetch to choose
/// between "Linked to `pkName`" (resolved) and "Linked to `pkId` (not in
/// current system)" (unresolved). When [state] is null, the helper conserves
/// the "unresolved" wording for any link without a fetch context — matching
/// the offline edge case where we cannot tell.
@visibleForTesting
String pkLinkManagementSearchLabelFor(
  AppLocalizations l10n,
  domain.Member m, {
  PkLinkManagementState? state,
}) {
  final pkUuid = m.pluralkitUuid?.trim();
  final pkId = m.pluralkitId?.trim();
  final hasLink = (pkUuid != null && pkUuid.isNotEmpty) ||
      (pkId != null && pkId.isNotEmpty);
  final excluded = m.pluralkitSyncIgnored;

  PKMember? resolved;
  if (state != null && hasLink) {
    if (pkUuid != null && pkUuid.isNotEmpty) {
      resolved = state.pkMembersByUuid[pkUuid];
    }
    if (resolved == null && pkId != null && pkId.isNotEmpty) {
      resolved = state.pkMembersById[pkId];
    }
  }

  if (excluded && hasLink) {
    final pkName = resolved?.displayName ?? resolved?.name;
    if (pkName != null) {
      return l10n.pkLinkManagementMemberStateExcludedLinked(pkName);
    }
    return l10n.pkLinkManagementMemberStateExcludedLinked(
      m.pluralkitDisplayName ?? pkId ?? pkUuid ?? '',
    );
  }
  if (excluded) return l10n.pkLinkManagementMemberStateExcludedUnlinked;
  if (hasLink) {
    if (resolved != null) {
      return l10n.pkLinkManagementMemberStateLinked(
        resolved.displayName ?? resolved.name,
      );
    }
    return l10n.pkLinkManagementMemberStateUnresolved(pkId ?? pkUuid ?? '');
  }
  return l10n.pkLinkManagementMemberStateNotLinked;
}

// Suppress the unused-element warning for `_pkSearchKey`: it's a helper used
// only by [_pickPkMember] and tests via the `__pk__` prefix would be brittle
// to reproduce; the explicit dependency on `PKMember.uuid` keeps the key in
// sync.

