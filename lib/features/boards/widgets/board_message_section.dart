import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/widgets/post_tile.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider;
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Board Messages section shown on the member detail screen.
///
/// Mirrors the structure of [NotesSection]: a header row with an icon, title,
/// and `+` button, followed by up to 3 recent public posts. If 4 or more
/// public posts exist, a "See all" link is shown below the list.
///
/// Returns [SizedBox.shrink] when [boardsEnabledProvider] is false.
class BoardMessageSection extends ConsumerWidget {
  const BoardMessageSection({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardsEnabled = ref.watch(boardsEnabledProvider);
    if (!boardsEnabled) return const SizedBox.shrink();

    final sectionAsync = ref.watch(memberBoardSectionProvider(memberId));
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // Resolve the current viewer for permission checks inside PostTile.
    final speakingAsId = ref.watch(speakingAsProvider);
    final viewerAsync = speakingAsId != null
        ? ref.watch(memberByIdProvider(speakingAsId))
        : const AsyncValue<Member?>.data(null);
    final viewerMember = viewerAsync.value;

    // Resolve the profile member for the tooltip name.
    final profileMemberAsync = ref.watch(memberByIdProvider(memberId));
    final profileMemberName =
        profileMemberAsync.value?.name ?? memberId;

    return sectionAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (section) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Section header ──────────────────────────────────────────
              Semantics(
                header: true,
                child: Row(
                  children: [
                    Icon(
                      AppIcons.navBoards,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.memberSectionBoardMessages,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    PrismInlineIconButton(
                      icon: AppIcons.add,
                      iconSize: 20,
                      color: theme.colorScheme.primary,
                      onPressed: () => _openCompose(context),
                      tooltip: l10n.memberBoardAddPost(profileMemberName),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ── Posts list or empty state ────────────────────────────────
              if (section.publicPosts.isEmpty)
                SizedBox(
                  width: double.infinity,
                  child: PrismSurface(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        l10n.memberBoardEmpty,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: PrismGroupedSectionCard(
                    child: Column(
                      children: [
                        for (var i = 0;
                            i < section.publicPosts.length;
                            i++) ...[
                          if (i > 0) const Divider(height: 1),
                          PostTile(
                            post: section.publicPosts[i],
                            viewerMember: viewerMember,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // ── "See all" link at ≥ 4 posts ─────────────────────────────
              if (section.totalPublic >= 4) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => context.go('/boards/member/$memberId'),
                  child: Text(
                    l10n.memberBoardSeeAll(section.totalPublic),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _openCompose(BuildContext context) {
    // TODO(E2): Replace with:
    //   ComposePostSheet.show(context,
    //     defaultTargetMemberId: memberId, defaultAudience: 'public')
    // once E2 lands.
    PrismToast.show(context, message: 'Compose coming soon');
  }
}
