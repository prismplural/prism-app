import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/media_state_providers.dart';
import 'package:prism_plurality/features/chat/widgets/media/image_viewer.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/services/bio_image_processor.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/settings/utils/tag_reference_rewriter.dart';
import 'package:prism_plurality/features/settings/utils/tag_usage_scan.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/markdown/markdown_preview.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/remote_image_fetcher.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/detail_side_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/clamped_body.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_popup_menu.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// Navigation branch for the Media library screen, which is mounted in more
/// than one route tree (pushed under Settings, or the optional Media tab).
enum MediaNavigationBranch { settings, media }

// ── Providers ─────────────────────────────────────────────────────────────────

final _allChatMediaProvider = StreamProvider.autoDispose<List<MediaAttachment>>(
  (ref) => ref.watch(mediaAttachmentRepositoryProvider).watchAllChatMedia(),
);

final _imageMarkdownBoardPostsProvider = StreamProvider.autoDispose(
  (ref) =>
      ref.watch(databaseProvider).memberBoardPostsDao.watchImageMarkdownPosts(),
);

/// Computes where each library tag is referenced, across every surface that
/// can contain `![](tag)`: bios, notes, group descriptions, long-text custom
/// fields, chat messages, and board posts. Returns tag → human-readable usage
/// labels.
///
/// The first four sources are bounded and scanned in memory. Chat could be
/// huge, so it's narrowed via a `content LIKE '%![%'` query and reported as a
/// count.
final tagUsageProvider = FutureProvider.autoDispose
    .family<Map<String, List<TagUsageRef>>, AppLocalizations>((
      ref,
      l10n,
    ) async {
      // Source the referencing surfaces from each provider's CURRENT value
      // (`.value`) rather than awaiting `.future`. Awaiting `.future` on a
      // stream provider that nothing else is watching (notes/groups/fields aren't
      // watched by this screen) can stall: the read initializes the provider and
      // blocks on its first emission, and that single stuck await previously
      // blanked ALL usage (every image showed "Unused"). Reading the current value
      // can't hang — if a source isn't loaded yet this recomputes when it emits
      // (we watch them), and a source that errors just contributes nothing instead
      // of killing the whole scan.
      final library = ref.watch(imageLibraryProvider).value ?? const [];
      final tags = library.map((a) => a.tag).where((t) => t.isNotEmpty).toSet();
      if (tags.isEmpty) return const {};

      final members = ref.watch(allMembersProvider).value ?? const [];
      final notes = ref.watch(allNotesProvider).value ?? const [];
      final groups = ref.watch(allGroupsProvider).value ?? const [];
      final fields = ref.watch(customFieldsProvider).value ?? const [];
      final boardPosts =
          ref.watch(_imageMarkdownBoardPostsProvider).value ?? const [];

      final memberName = {for (final m in members) m.id: m.name};
      final fieldName = {for (final f in fields) f.id: f.name};

      // Each source carries the label + route to jump to if it references a tag.
      // Bio/note/group/custom-field use the Settings-tab detail routes so the jump
      // pushes within Settings (where Media lives) and system back returns to the
      // Media screen. Chat has no in-Settings route, so it switches tabs (handled
      // in _showUsage by kind).
      final sources = <TagUsageSource>[];
      for (final m in members) {
        final bio = m.bio;
        if (bio != null && bio.isNotEmpty) {
          sources.add(
            TagUsageSource(
              text: bio,
              kind: TagUsageKind.bio,
              label: l10n.mediaUsageLabelBio(m.name),
              route: AppRoutePaths.settingsMember(m.id),
            ),
          );
        }
      }
      for (final n in notes) {
        final t = n.title.trim();
        sources.add(
          TagUsageSource(
            text: n.body,
            kind: TagUsageKind.note,
            label: t.isNotEmpty
                ? l10n.mediaUsageLabelNote(t)
                : l10n.mediaUsageLabelUntitledNote,
            route: AppRoutePaths.settingsNote(n.id),
          ),
        );
      }
      for (final g in groups) {
        final desc = g.description;
        if (desc != null && desc.isNotEmpty) {
          sources.add(
            TagUsageSource(
              text: desc,
              kind: TagUsageKind.group,
              label: g.name,
              route: AppRoutePaths.settingsGroup(g.id),
            ),
          );
        }
      }

      // Custom-field values + chat + board posts are one-shot DB reads — guard each
      // so a failure contributes nothing rather than blanking the whole result.
      try {
        final values = await ref
            .read(customFieldsRepositoryProvider)
            .getAllValues();
        if (!ref.mounted) return const {};
        for (final v in values) {
          final mName =
              memberName[v.memberId] ?? l10n.mediaUsageLabelUnknownMember;
          final fName =
              fieldName[v.customFieldId] ?? l10n.mediaUsageLabelUnknownField;
          sources.add(
            TagUsageSource(
              text: v.value,
              kind: TagUsageKind.customField,
              label: l10n.mediaUsageLabelCustomField(mName, fName),
              route: AppRoutePaths.settingsMember(v.memberId),
            ),
          );
        }
      } catch (e) {
        if (!ref.mounted) return const {};
        debugPrint('[tagUsage] custom-field values read failed: $e');
      }

      if (!ref.mounted) return const {};
      try {
        final chatMessages = await ref
            .read(databaseProvider)
            .chatMessagesDao
            .imageMarkdownMessages();
        if (!ref.mounted) return const {};
        for (final msg in chatMessages) {
          final preview = stripImageMarkdown(msg.content).trim();
          sources.add(
            TagUsageSource(
              text: msg.content,
              kind: TagUsageKind.chat,
              label: preview.isEmpty
                  ? l10n.mediaUsageLabelChatMessage
                  : (preview.length > 60
                        ? '${preview.substring(0, 60)}…'
                        : preview),
              route:
                  '${AppRoutePaths.chatConversation(msg.conversationId)}'
                  '?messageId=${msg.id}',
            ),
          );
        }
      } catch (e) {
        if (!ref.mounted) return const {};
        debugPrint('[tagUsage] chat messages read failed: $e');
      }

      for (final post in boardPosts) {
        final title = post.title?.trim() ?? '';
        final preview = stripImageMarkdown(post.body).trim();
        final label = title.isNotEmpty
            ? l10n.mediaUsageLabelBoardPost(title)
            : (preview.isEmpty
                  ? l10n.mediaUsageLabelBoardPostUntitled
                  : l10n.mediaUsageLabelBoardPost(
                      preview.length > 60
                          ? '${preview.substring(0, 60)}…'
                          : preview,
                    ));
        sources.add(
          TagUsageSource(
            text: post.body,
            kind: TagUsageKind.boardPost,
            label: label,
            route: AppRoutePaths.boardPost(post.id),
          ),
        );
      }

      return scanTagUsage(tags: tags, sources: sources);
    });

enum _AddSource { camera, photoLibrary, file, url }

// ── Screen ────────────────────────────────────────────────────────────────────

class MediaSettingsScreen extends ConsumerWidget {
  const MediaSettingsScreen({
    super.key,
    this.branch = MediaNavigationBranch.settings,
  });

  final MediaNavigationBranch branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final libraryAsync = ref.watch(imageLibraryProvider);
    final chatAsync = ref.watch(_allChatMediaProvider);
    final membersAsync = ref.watch(allMembersProvider);

    return PrismPageScaffold(
      topBarMaxWidth: PrismTokens.contentMaxWidth,
      topBar: PrismTopBar(
        title: l10n.mediaScreenTitle,
        showBackButton: branch == MediaNavigationBranch.settings,
        actions: [
          PrismPopupMenu<_AddSource>(
            icon: AppIcons.add,
            tooltip: l10n.mediaAddImageTooltip,
            width: 200,
            items: [
              PrismMenuItem(
                value: _AddSource.camera,
                label: l10n.mediaSourceCamera,
                icon: AppIcons.cameraAlt,
              ),
              PrismMenuItem(
                value: _AddSource.photoLibrary,
                label: l10n.mediaSourcePhotoLibrary,
                icon: AppIcons.photoLibrary,
              ),
              PrismMenuItem(
                value: _AddSource.file,
                label: l10n.mediaSourceFile,
                icon: AppIcons.fileUploadOutlined,
              ),
              PrismMenuItem(
                value: _AddSource.url,
                label: l10n.mediaSourceUrl,
                icon: AppIcons.link,
              ),
            ],
            onSelected: (source) => _handleAddImage(context, ref, source),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: libraryAsync.when(
        loading: () => Center(
          child: PrismSpinner(color: Theme.of(context).colorScheme.primary),
        ),
        error: (e, _) => Center(child: Text(l10n.errorWithDetail('$e'))),
        data: (libraryImages) => chatAsync.when(
          loading: () => Center(
            child: PrismSpinner(color: Theme.of(context).colorScheme.primary),
          ),
          error: (e, _) => Center(child: Text(l10n.errorWithDetail('$e'))),
          data: (chatAttachments) {
            final allMembers = membersAsync.asData?.value ?? const <Member>[];

            // Tag → human-readable usage labels across all surfaces. Async
            // (chat is queried), so default to empty while it resolves.
            final tagUsage =
                ref.watch(tagUsageProvider(context.l10n)).value ?? const {};

            // Avatars / banners summary.
            final avatarMembers = allMembers
                .where((m) => m.avatarImageData != null)
                .toList();
            final bannerMembers = allMembers
                .where((m) => m.profileHeaderImageData != null)
                .toList();
            final avatarBytes = avatarMembers.fold<int>(
              0,
              (s, m) => s + (m.avatarImageData?.length ?? 0),
            );
            final bannerBytes = bannerMembers.fold<int>(
              0,
              (s, m) => s + (m.profileHeaderImageData?.length ?? 0),
            );

            final hasLibrary = libraryImages.isNotEmpty;
            final hasChat = chatAttachments.isNotEmpty;
            final hasAvatars =
                avatarMembers.isNotEmpty || bannerMembers.isNotEmpty;

            if (!hasLibrary && !hasChat && !hasAvatars) {
              return Center(child: Text(l10n.mediaNoStoredMedia));
            }

            final totalEncryptedBytes =
                libraryImages.fold<int>(0, (s, a) => s + a.sizeBytes) +
                chatAttachments.fold<int>(0, (s, a) => s + a.sizeBytes);
            final totalEncryptedCount =
                libraryImages.length + chatAttachments.length;

            return ClampedBody(
              child: ListView(
                padding: EdgeInsets.only(top: 8, bottom: NavBarInset.of(context)),
                children: [
                // ── Storage overview ──────────────────────────────────────
                PrismSection(
                  title: l10n.mediaSectionStorage,
                  child: PrismSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StorageRow(
                          icon: AppIcons.photoLibrary,
                          label: l10n.mediaStorageEncryptedMedia,
                          summary:
                              '${l10n.mediaSummaryItems(totalEncryptedCount)}'
                              ' · ${_formatBytes(totalEncryptedBytes)}',
                        ),
                        if (hasAvatars) ...[
                          const SizedBox(height: 10),
                          _StorageRow(
                            icon: AppIcons.personOutline,
                            label: l10n.mediaStorageMemberData,
                            summary: _buildAvatarSummary(
                              l10n,
                              avatarMembers.length,
                              avatarBytes,
                              bannerMembers.length,
                              bannerBytes,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── Image library ────────────────────────────────────────
                if (hasLibrary)
                  PrismSection(
                    title: l10n.mediaSectionImageLibrary,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final img in libraryImages)
                          _LibraryImageCard(
                            attachment: img,
                            branch: branch,
                            usedBy: tagUsage[img.tag] ?? [],
                            onEditTag: () => _editTag(
                              context,
                              ref,
                              img,
                              tagUsage[img.tag] ?? const [],
                            ),
                            onReplace: () => _replaceImage(context, ref, img),
                            onDelete: () =>
                                _deleteLibraryImage(context, ref, img.id),
                          ),
                      ],
                    ),
                  ),

                // ── Chat images ──────────────────────────────────────────
                if (hasChat)
                  PrismSection(
                    title: l10n.mediaSectionChatImages,
                    child: PrismSectionCard(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final attachment in chatAttachments)
                              _MediaThumbnail(
                                attachment: attachment,
                                onDelete: () =>
                                    _deleteChat(context, ref, attachment.id),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── Avatars & banners (summary) ──────────────────────────
                if (hasAvatars)
                  PrismSection(
                    title: l10n.mediaSectionAvatarsBanners,
                    footer: Text(l10n.mediaAvatarsBannersFooter),
                    child: PrismSectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (avatarMembers.isNotEmpty)
                            _StorageRow(
                              icon: AppIcons.personOutline,
                              label: l10n.mediaLabelAvatars,
                              summary:
                                  '${l10n.mediaSummaryAvatars(avatarMembers.length)}'
                                  ' · ${_formatBytes(avatarBytes)}',
                            ),
                          if (avatarMembers.isNotEmpty &&
                              bannerMembers.isNotEmpty)
                            const SizedBox(height: 10),
                          if (bannerMembers.isNotEmpty)
                            _StorageRow(
                              icon: AppIcons.imageOutlined,
                              label: l10n.mediaLabelBanners,
                              summary:
                                  '${l10n.mediaSummaryBanners(bannerMembers.length)}'
                                  ' · ${_formatBytes(bannerBytes)}',
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Scan all members' bios for tag references, returning tag → [member names].
  Future<void> _handleAddImage(
    BuildContext context,
    WidgetRef ref,
    _AddSource source,
  ) async {
    Uint8List? bytes;
    // The original URL when the source is a URL import — persisted as
    // source_url for backup/export parity with BioImageImporter. Empty for
    // device-picked images.
    String sourceUrl = '';

    switch (source) {
      case _AddSource.camera:
        final picked = await ImagePicker().pickImage(
          source: ImageSource.camera,
        );
        if (picked == null || !context.mounted) return;
        bytes = await picked.readAsBytes();

      case _AddSource.photoLibrary:
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        if (picked == null || !context.mounted) return;
        bytes = await picked.readAsBytes();

      case _AddSource.file:
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        // ImagePicker.gallery is the closest cross-platform equivalent.
        // On desktop, PrismFileDialogService could be used instead.
        if (picked == null || !context.mounted) return;
        bytes = await picked.readAsBytes();

      case _AddSource.url:
        final urlResult = await _showUrlDialog(context);
        if (urlResult == null || !context.mounted) return;
        bytes = await fetchRemoteImageBytes(urlResult);
        if (bytes == null && context.mounted) {
          PrismToast.error(
            context,
            message: context.l10n.mediaFetchFromUrlFailed,
          );
          return;
        }
        sourceUrl = urlResult;
    }

    if (bytes == null || !context.mounted) return;
    final imageBytes = bytes;

    // Tag dialog with thumbnail preview. The dialog body owns its controllers
    // (see _AddToLibraryDialog) so they're disposed only when the route is
    // fully gone — never synchronously mid-exit-transition, which crashes when
    // the dismissing keyboard rebuilds the field against a disposed controller.
    final result = await PrismDialog.show<({String tag, String? altText})>(
      context: context,
      title: context.l10n.mediaAddToLibraryTitle,
      builder: (_) => _AddToLibraryDialog(imageBytes: imageBytes),
    );

    if (result == null || !context.mounted) return;

    // Normalize + collision-check the tag with the same rules the staging
    // processor uses, so a tag typed here can't contain `)`/`#` (which would
    // break `![](tag)` parsing) or collide with an existing tag (which would
    // make references resolve nondeterministically across synced devices).
    final List<MediaAttachment> library;
    try {
      library = await readImageLibrarySnapshot(ref);
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.mediaAddImageFailed('$e'),
        );
      }
      return;
    }
    if (!context.mounted) return;

    final existingTags = library.map((a) => a.tag).toSet();
    String tag;
    if (result.tag.isNotEmpty) {
      final normalized = BioImageProcessor.normalizeTag(result.tag);
      if (normalized.isEmpty) {
        PrismToast.error(
          context,
          message: context.l10n.mediaTagNoUsableCharacters,
        );
        return;
      }
      if (existingTags.contains(normalized)) {
        PrismToast.error(
          context,
          message: context.l10n.mediaTagAlreadyInUse(normalized),
        );
        return;
      }
      tag = normalized;
    } else {
      do {
        tag = 'img-${const Uuid().v4().substring(0, 8)}';
      } while (existingTags.contains(tag));
    }

    try {
      final mediaService = ref.read(mediaServiceProvider);
      final repo = ref.read(mediaAttachmentRepositoryProvider);

      final prepared = await mediaService.prepareBioImage(bytes);
      await mediaService.uploadBioImage(prepared);

      final attachmentId = const Uuid().v4();
      await repo.create(
        MediaAttachment(
          id: attachmentId,
          memberId: '',
          messageId: '',
          tag: tag,
          mediaId: prepared.mediaId,
          mediaType: 'image',
          encryptionKeyB64: base64Encode(prepared.encryptionKey),
          contentHash: prepared.contentHash,
          plaintextHash: prepared.plaintextHash,
          mimeType: prepared.mimeType,
          sizeBytes: prepared.sizeBytes,
          width: prepared.width,
          height: prepared.height,
          durationMs: 0,
          blurhash: prepared.blurhash,
          waveformB64: '',
          thumbnailMediaId: '',
          sourceUrl: sourceUrl,
          previewUrl: '',
        ),
      );

      if (context.mounted) {
        PrismToast.show(
          context,
          message: context.l10n.mediaAddedToLibrary(tag),
        );
      }
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.mediaAddImageFailed('$e'),
        );
      }
    }
  }

  Future<String?> _showUrlDialog(BuildContext context) {
    final l10n = context.l10n;
    return PrismDialog.show<String>(
      context: context,
      title: l10n.mediaImageUrlTitle,
      builder: (_) => _PromptDialog(
        hintText: l10n.mediaImageUrlHint,
        confirmLabel: l10n.mediaFetchButton,
        keyboardType: TextInputType.url,
      ),
    );
  }

  Future<void> _deleteLibraryImage(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final confirmed = await _confirmDelete(context);
    if (!confirmed || !context.mounted) return;
    final repo = ref.read(mediaAttachmentRepositoryProvider);
    await repo.softDeleteBioMedia(id);
  }

  Future<void> _deleteChat(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final confirmed = await _confirmDelete(context);
    if (!confirmed || !context.mounted) return;
    final repo = ref.read(mediaAttachmentRepositoryProvider);
    await repo.delete(id);
  }

  Future<void> _editTag(
    BuildContext context,
    WidgetRef ref,
    MediaAttachment attachment,
    List<TagUsageRef> usedBy,
  ) async {
    final l10n = context.l10n;
    final newTag = await PrismDialog.show<String>(
      context: context,
      title: l10n.mediaMenuEditTag,
      builder: (_) => _PromptDialog(
        hintText: l10n.mediaEditTagHint,
        confirmLabel: l10n.save,
        initialText: attachment.tag,
      ),
    );

    if (newTag == null || newTag.isEmpty || !context.mounted) return;

    // Apply the same normalization + collision rules as every other tag-writing
    // path (a raw `)`/`#` here would break `![](tag)` resolution; a duplicate
    // would resolve nondeterministically across synced devices).
    final normalized = BioImageProcessor.normalizeTag(newTag);
    if (normalized.isEmpty) {
      PrismToast.error(context, message: l10n.mediaTagNoUsableCharacters);
      return;
    }
    if (normalized == attachment.tag) return;

    final List<MediaAttachment> library;
    try {
      library = await readImageLibrarySnapshot(ref);
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(context, message: l10n.errorWithDetail('$e'));
      }
      return;
    }
    if (!context.mounted) return;

    if (library.any((a) => a.id != attachment.id && a.tag == normalized)) {
      PrismToast.error(context, message: l10n.mediaTagAlreadyInUse(normalized));
      return;
    }

    final oldTag = attachment.tag;

    // If the tag is referenced anywhere, let the user choose what happens to
    // those refs. Repointing them keeps the images showing; leaving them is
    // intentional when renaming to free up the name for a *different* image
    // (the old `![](oldTag)` refs then resolve to whatever next takes oldTag).
    var rewrite = false;
    if (usedBy.isNotEmpty) {
      final choice = await _confirmRenameReferences(
        context,
        count: usedBy.length,
        oldTag: oldTag,
        newTag: normalized,
      );
      if (choice == null || !context.mounted) return; // cancelled
      rewrite = choice;
    }

    final repo = ref.read(mediaAttachmentRepositoryProvider);
    await repo.updateTag(attachment.id, normalized);

    if (!rewrite) {
      if (context.mounted) {
        PrismToast.success(context, message: l10n.mediaTagRenamed);
      }
      return;
    }

    // Rewrite every `![](oldTag)` / `![](oldTag#frag)` reference across all
    // surfaces to point at the new tag. Not atomic by design: both the
    // rewritten refs and the renamed row leave things resolvable. Failures on
    // any one record are swallowed so the rest still get updated (the toast
    // count reflects what actually landed).
    final updated = await _rewriteTagReferences(ref, oldTag, normalized);

    if (!context.mounted) return;
    PrismToast.success(
      context,
      message: updated == 0
          ? l10n.mediaTagRenamed
          : l10n.mediaTagRenamedWithReferences(updated),
    );
  }

  /// Asks whether to repoint existing references when renaming an in-use tag.
  /// Returns `true` (update refs), `false` (leave them), or `null` (cancel).
  Future<bool?> _confirmRenameReferences(
    BuildContext context, {
    required int count,
    required String oldTag,
    required String newTag,
  }) {
    final nav = Navigator.of(context, rootNavigator: true);
    final l10n = context.l10n;
    return PrismDialog.show<bool>(
      context: context,
      title: l10n.mediaUpdateReferencesTitle,
      message: l10n.mediaUpdateReferencesMessage(count, oldTag, newTag),
      builder: (_) => const SizedBox.shrink(),
      actions: [
        PrismButton(
          label: l10n.cancel,
          tone: PrismButtonTone.outlined,
          onPressed: () => nav.pop(null),
        ),
        PrismButton(
          label: l10n.mediaActionLeave,
          tone: PrismButtonTone.outlined,
          onPressed: () => nav.pop(false),
        ),
        PrismButton(
          label: l10n.mediaActionUpdate,
          tone: PrismButtonTone.filled,
          onPressed: () => nav.pop(true),
        ),
      ],
    );
  }

  /// Rewrites `![](oldTag…)` image refs to `![](newTag…)` across bios, custom
  /// field values, chat messages, notes, group descriptions, and board posts.
  /// Returns the number of records actually updated.
  ///
  /// Resolves the repos/DAO from `ref` and delegates the fan-out to
  /// [rewriteTagReferencesAcrossSurfaces] (which is widget-free and
  /// integration-tested directly). Reads there use one-shot repo getters
  /// (never `await`ing a stream provider's `.future`, which can stall — see
  /// git fix 1d3b49ab); each surface is guarded so a single failure
  /// contributes nothing rather than aborting the whole pass.
  Future<int> _rewriteTagReferences(
    WidgetRef ref,
    String oldTag,
    String newTag,
  ) {
    return rewriteTagReferencesAcrossSurfaces(
      memberRepo: ref.read(memberRepositoryProvider),
      notesRepo: ref.read(notesRepositoryProvider),
      groupsRepo: ref.read(memberGroupsRepositoryProvider),
      fieldsRepo: ref.read(customFieldsRepositoryProvider),
      chatRepo: ref.read(chatMessageRepositoryProvider),
      chatDao: ref.read(databaseProvider).chatMessagesDao,
      boardPostsRepo: ref.read(memberBoardPostsRepositoryProvider),
      boardPostsDao: ref.read(databaseProvider).memberBoardPostsDao,
      oldTag: oldTag,
      newTag: newTag,
    );
  }

  Future<void> _replaceImage(
    BuildContext context,
    WidgetRef ref,
    MediaAttachment attachment,
  ) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return;

    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;

    try {
      final mediaService = ref.read(mediaServiceProvider);
      final repo = ref.read(mediaAttachmentRepositoryProvider);

      // Capture the previous mediaId so we can evict its now-orphaned cached
      // blob after the record is repointed below.
      final previousMediaId = attachment.mediaId;

      // Prepare the new image (compress + encrypt).
      final prepared = await mediaService.prepareBioImage(bytes);

      // Upload new ciphertext.
      await mediaService.uploadBioImage(prepared);

      // Update the existing record in place (same id + tag) so all references
      // resolve to the new image. A create() here would collide on the PK.
      // Preserve the prior sourceUrl — replacement swaps the bytes, not the
      // image's provenance (for backup/export consistency).
      await repo.replaceMedia(
        attachment.id,
        attachment.copyWith(
          mediaId: prepared.mediaId,
          encryptionKeyB64: base64Encode(prepared.encryptionKey),
          contentHash: prepared.contentHash,
          plaintextHash: prepared.plaintextHash,
          mimeType: prepared.mimeType,
          sizeBytes: prepared.sizeBytes,
          width: prepared.width,
          height: prepared.height,
          blurhash: prepared.blurhash,
        ),
      );

      // Reclaim the old blob immediately — nothing references previousMediaId
      // anymore. Evict it from both the on-disk encrypted cache and the
      // in-memory decrypted-bytes cache. The remote relay blob has no
      // owned-media delete signal, so its cleanup relies on the 90-day TTL.
      if (previousMediaId.isNotEmpty && previousMediaId != prepared.mediaId) {
        await ref.read(downloadManagerProvider).evictEncrypted(previousMediaId);
        evictMediaCache(previousMediaId);
      }
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.mediaReplaceImageFailed('$e'),
        );
      }
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final l10n = context.l10n;
    return await PrismDialog.confirm(
      context: context,
      title: l10n.mediaDeleteImageTitle,
      message: l10n.mediaDeleteImageMessage,
      confirmLabel: l10n.mediaMenuDelete,
      destructive: true,
    );
  }

  static String _buildAvatarSummary(
    AppLocalizations l10n,
    int avatarCount,
    int avatarBytes,
    int bannerCount,
    int bannerBytes,
  ) {
    final parts = <String>[];
    if (avatarCount > 0) {
      parts.add(
        '${l10n.mediaSummaryAvatars(avatarCount)} · '
        '${_formatBytes(avatarBytes)}',
      );
    }
    if (bannerCount > 0) {
      parts.add(
        '${l10n.mediaSummaryBanners(bannerCount)} · '
        '${_formatBytes(bannerBytes)}',
      );
    }
    return parts.join(', ');
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ── Library image card (half-width) ──────────────────────────────────────────

class _LibraryImageCard extends ConsumerStatefulWidget {
  const _LibraryImageCard({
    required this.attachment,
    required this.branch,
    required this.usedBy,
    required this.onEditTag,
    required this.onReplace,
    required this.onDelete,
  });

  final MediaAttachment attachment;
  final MediaNavigationBranch branch;
  final List<TagUsageRef> usedBy;
  final VoidCallback onEditTag;
  final VoidCallback onReplace;
  final VoidCallback onDelete;

  @override
  ConsumerState<_LibraryImageCard> createState() => _LibraryImageCardState();
}

class _LibraryImageCardState extends ConsumerState<_LibraryImageCard> {
  final GlobalKey<BlurPopupAnchorState> _menuKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attachment = widget.attachment;
    final params = (
      mediaId: attachment.mediaId,
      encryptionKeyB64: attachment.encryptionKeyB64,
      ciphertextHash: attachment.contentHash,
      plaintextHash: attachment.plaintextHash,
    );
    final imageAsync = ref.watch(mediaFileProvider(params));

    // PrismSection already applies pageHorizontalPadding on both sides.
    // Clamp to contentMaxWidth so the grid matches the clamped body width.
    final availableWidth =
        math.min(
          MediaQuery.of(context).size.width,
          PrismTokens.contentMaxWidth,
        ) - PrismTokens.pageHorizontalPadding * 2;
    final cardWidth = (availableWidth - 10 * 2) / 3;

    return SizedBox(
      width: cardWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image thumbnail.
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: SizedBox(
                width: cardWidth,
                height: cardWidth * 0.65,
                child: imageAsync.when(
                  loading: () => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Center(
                      child: PrismSpinner(
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  error: (_, _) => Center(
                    child: Icon(
                      AppIcons.imageBroken,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  data: (bytes) {
                    if (bytes == null) {
                      return Center(
                        child: Icon(
                          AppIcons.imageBroken,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    }
                    // Decode to roughly the on-screen size rather than the
                    // full (up to 2048px) bitmap — these are small thumbnails.
                    final dpr = MediaQuery.devicePixelRatioOf(context);
                    return GestureDetector(
                      onTap: () => ImageViewer.show(context, imageBytes: bytes),
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        cacheWidth: (cardWidth * dpr).round(),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Tag + usage + menu button.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 2, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.tag,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        if (widget.usedBy.isNotEmpty)
                          Text(
                            widget.usedBy.length == 1
                                ? widget.usedBy.first.label
                                : context.l10n.mediaUsageUsedInPlaces(
                                    widget.usedBy.length,
                                  ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        else
                          Text(
                            context.l10n.mediaUsageUnused,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      final l10n = context.l10n;
                      final items = <PrismMenuItem<String>>[
                        if (widget.usedBy.isNotEmpty)
                          PrismMenuItem(
                            value: 'view-usage',
                            label: l10n.mediaMenuViewUsage,
                            icon: AppIcons.preview,
                          ),
                        PrismMenuItem(
                          value: 'copy',
                          label: l10n.mediaMenuCopyCode,
                          icon: AppIcons.copy,
                        ),
                        PrismMenuItem(
                          value: 'edit-tag',
                          label: l10n.mediaMenuEditTag,
                          icon: AppIcons.edit,
                        ),
                        PrismMenuItem(
                          value: 'replace',
                          label: l10n.mediaMenuReplaceImage,
                          icon: AppIcons.imageOutlined,
                        ),
                        PrismMenuItem(
                          value: 'delete',
                          label: l10n.mediaMenuDelete,
                          icon: AppIcons.deleteOutline,
                          destructive: true,
                        ),
                      ];
                      return BlurPopupAnchor(
                        key: _menuKey,
                        trigger: BlurPopupTrigger.manual,
                        width: 210,
                        itemCount: items.length,
                        itemBuilder: (context, index, close) {
                          final item = items[index];
                          final iconColor = item.destructive
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurface;
                          return PrismListRow(
                            dense: true,
                            destructive: item.destructive,
                            leading: Icon(
                              item.icon,
                              size: 20,
                              color: iconColor,
                            ),
                            title: Text(item.label),
                            onTap: () {
                              close();
                              switch (item.value) {
                                case 'view-usage':
                                  _showUsage();
                                case 'copy':
                                  Clipboard.setData(
                                    ClipboardData(
                                      text: '![](${attachment.tag})',
                                    ),
                                  );
                                  PrismToast.show(
                                    context,
                                    message: context.l10n.mediaCopiedReference(
                                      '![](${attachment.tag})',
                                    ),
                                  );
                                case 'edit-tag':
                                  widget.onEditTag();
                                case 'replace':
                                  widget.onReplace();
                                case 'delete':
                                  widget.onDelete();
                              }
                            },
                          );
                        },
                        child: PrismIconButton(
                          icon: AppIcons.moreVert,
                          size: 28,
                          onPressed: () => _menuKey.currentState?.show(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUsage() {
    // Wide windows open the usage list as a modal side sheet; narrow windows
    // push it onto the active branch's navigator (back retraces usage list →
    // Media) using the branch-native route.
    if (shouldUseDetailSideSheet(context)) {
      showDetailSideSheet(
        context,
        builder: (_) => TagUsageScreen(usages: widget.usedBy),
      );
    } else {
      unawaited(
        context.push(
          widget.branch == MediaNavigationBranch.media
              ? AppRoutePaths.mediaUsage
              : AppRoutePaths.settingsMediaUsage,
          extra: widget.usedBy,
        ),
      );
    }
  }
}

// ── Storage summary row ──────────────────────────────────────────────────────

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.icon,
    required this.label,
    required this.summary,
  });

  final IconData icon;
  final String label;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(summary, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Chat media thumbnail ─────────────────────────────────────────────────────

class _MediaThumbnail extends ConsumerWidget {
  const _MediaThumbnail({required this.attachment, required this.onDelete});

  final MediaAttachment attachment;
  final VoidCallback onDelete;

  static const double _size = 88;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final params = (
      mediaId: attachment.mediaId,
      encryptionKeyB64: attachment.encryptionKeyB64,
      ciphertextHash: attachment.contentHash,
      plaintextHash: attachment.plaintextHash,
    );
    final imageAsync = ref.watch(mediaFileProvider(params));

    // Actions shared by the thumbnail's long-press menu and the full-screen
    // viewer's dropdown. "Jump to message" only applies while the attachment is
    // still linked to a message; otherwise it's delete-only.
    final l10n = context.l10n;
    final hasMessage = attachment.messageId.isNotEmpty;
    final actions = <ImageViewerAction>[
      if (hasMessage)
        ImageViewerAction(
          label: l10n.mediaMenuJumpToMessage,
          icon: AppIcons.messageOutlined,
          onSelected: () => _jumpToMessage(context, ref),
        ),
      ImageViewerAction(
        label: l10n.mediaMenuDelete,
        icon: AppIcons.deleteOutline,
        destructive: true,
        onSelected: onDelete,
      ),
    ];

    return SizedBox(
      width: _size,
      height: _size,
      child: BlurPopupAnchor(
        trigger: BlurPopupTrigger.longPress,
        width: 210,
        itemCount: actions.length,
        itemBuilder: (context, index, close) {
          final action = actions[index];
          final iconColor = action.destructive
              ? theme.colorScheme.error
              : theme.colorScheme.onSurface;
          return PrismListRow(
            dense: true,
            destructive: action.destructive,
            leading: Icon(action.icon, size: 20, color: iconColor),
            title: Text(action.label),
            onTap: () {
              close();
              action.onSelected();
            },
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: imageAsync.when(
            loading: () => Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Center(
                child: PrismSpinner(
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            error: (_, _) => Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                AppIcons.imageBroken,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            data: (bytes) {
              if (bytes == null) {
                return Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    AppIcons.imageBroken,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              // Decode to roughly the on-screen size rather than the full
              // (up to 2048px) bitmap — this is an 88px thumbnail.
              final dpr = MediaQuery.devicePixelRatioOf(context);
              return GestureDetector(
                onTap: () => ImageViewer.show(
                  context,
                  imageBytes: bytes,
                  actions: actions,
                ),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  cacheWidth: (_size * dpr).round(),
                  semanticLabel: l10n.imageSemanticThumbnail,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Resolve the attachment's source message → its conversation, then navigate
  /// to that conversation scrolled to (and highlighting) the message. Mirrors
  /// the chat-search jump (`/chat/<id>?messageId=<id>`).
  Future<void> _jumpToMessage(BuildContext context, WidgetRef ref) async {
    final messageId = attachment.messageId;
    if (messageId.isEmpty) return;
    final message = await ref
        .read(databaseProvider)
        .chatMessagesDao
        .getMessageById(messageId);
    if (!context.mounted) return;
    if (message == null) {
      PrismToast.error(
        context,
        message: context.l10n.mediaMessageNoLongerExists,
      );
      return;
    }
    context.go(
      '${AppRoutePaths.chatConversation(message.conversationId)}'
      '?messageId=$messageId',
    );
  }
}

// ── Self-contained dialog bodies ─────────────────────────────────────────────
//
// These own their TextEditingControllers and dispose them in State.dispose(),
// which Flutter calls only when the dialog route is fully removed (after its
// exit transition). Disposing a controller synchronously right after the dialog
// future resolves crashes: the route is still animating out, and the dismissing
// keyboard rebuilds the still-mounted TextField, whose internal
// AnimatedBuilder(Listenable.merge([focusNode, controller])) re-subscribes to
// the now-disposed controller.

/// Add-to-library dialog: image preview + optional tag + optional alt text.
/// Pops `({String tag, String? altText})` on Add, or `null` on Cancel.
class _AddToLibraryDialog extends StatefulWidget {
  const _AddToLibraryDialog({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<_AddToLibraryDialog> createState() => _AddToLibraryDialogState();
}

class _AddToLibraryDialogState extends State<_AddToLibraryDialog> {
  final _tag = TextEditingController();
  final _alt = TextEditingController();

  @override
  void dispose() {
    _tag.dispose();
    _alt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context, rootNavigator: true);
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: Image.memory(widget.imageBytes, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 16),
        PrismTextField(
          controller: _tag,
          autofocus: true,
          hintText: l10n.mediaTagFieldHint,
          textCapitalization: TextCapitalization.none,
        ),
        const SizedBox(height: 8),
        PrismTextField(
          controller: _alt,
          hintText: l10n.mediaAltTextFieldHint,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            PrismButton(
              label: l10n.cancel,
              tone: PrismButtonTone.outlined,
              onPressed: () => nav.pop(null),
            ),
            PrismButton(
              label: l10n.add,
              tone: PrismButtonTone.filled,
              onPressed: () => nav.pop((
                tag: _tag.text.trim(),
                altText: _alt.text.trim().isEmpty ? null : _alt.text.trim(),
              )),
            ),
          ],
        ),
      ],
    );
  }
}

/// Single-field prompt dialog. Pops the trimmed text on confirm, `null` on
/// cancel. Used for URL entry and tag editing.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.hintText,
    required this.confirmLabel,
    this.initialText = '',
    this.keyboardType,
  });

  final String hintText;
  final String confirmLabel;
  final String initialText;
  final TextInputType? keyboardType;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context, rootNavigator: true);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PrismTextField(
          controller: _controller,
          autofocus: true,
          hintText: widget.hintText,
          keyboardType: widget.keyboardType,
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            PrismButton(
              label: context.l10n.cancel,
              tone: PrismButtonTone.outlined,
              onPressed: () => nav.pop(null),
            ),
            PrismButton(
              label: widget.confirmLabel,
              tone: PrismButtonTone.filled,
              onPressed: () => nav.pop(_controller.text.trim()),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Image usage screen ───────────────────────────────────────────────────────

/// Full-screen list of every surface that references a library tag, tappable to
/// jump to it. Pushed as a Settings-branch route (see
/// [AppRoutePaths.settingsMediaUsage]) with the usages passed via `extra`, so it
/// stacks on the Media screen and the detail jumps stack on it — system back
/// retraces Media ← this list ← detail.
///
/// Bio/note/group/custom-field jumps `push` (staying in the Settings tab, back
/// returns here); chat lives in its own tab so it `go`es there.
class TagUsageScreen extends StatelessWidget {
  const TagUsageScreen({super.key, required this.usages});

  final List<TagUsageRef> usages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: l10n.mediaUsageScreenTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: usages.isEmpty
          ? Center(child: Text(l10n.mediaUsageNotUsedAnywhere))
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                NavBarInset.of(context) + 16,
              ),
              itemCount: usages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final usage = usages[index];
                return PrismSectionCard(
                  semanticLabel:
                      '${usage.label}. ${_usageKindLabel(l10n, usage.kind)}.',
                  onTap: () {
                    if (usage.kind == TagUsageKind.chat ||
                        usage.kind == TagUsageKind.boardPost) {
                      context.go(usage.route);
                    } else {
                      unawaited(context.push(usage.route));
                    }
                  },
                  child: Row(
                    children: [
                      Icon(
                        _usageIcon(usage.kind),
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              usage.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              _usageKindLabel(l10n, usage.kind),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        AppIcons.chevronRight,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

IconData _usageIcon(TagUsageKind kind) => switch (kind) {
  TagUsageKind.bio => AppIcons.personOutline,
  TagUsageKind.note => AppIcons.noteOutlined,
  TagUsageKind.group => AppIcons.group,
  TagUsageKind.customField => AppIcons.labelOutlined,
  TagUsageKind.chat => AppIcons.chatBubbleOutline,
  TagUsageKind.boardPost => AppIcons.forum,
};

String _usageKindLabel(AppLocalizations l10n, TagUsageKind kind) =>
    switch (kind) {
      TagUsageKind.bio => l10n.mediaUsageKindBio,
      TagUsageKind.note => l10n.mediaUsageKindNote,
      TagUsageKind.group => l10n.mediaUsageKindGroup,
      TagUsageKind.customField => l10n.mediaUsageKindCustomField,
      TagUsageKind.chat => l10n.mediaUsageKindChat,
      TagUsageKind.boardPost => l10n.mediaUsageKindBoardPost,
    };
