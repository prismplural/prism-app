import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/data/repositories/drift_media_attachment_repository.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/features/members/services/bio_image_processor.dart';

// ── Bio image processing state ────────────────────────────────────────────────

enum BioImageProcessingStatus { idle, processing, done, error }

class BioImageProcessingState {
  final BioImageProcessingStatus status;
  final int totalCount;
  final int completedCount;
  final String? errorMessage;

  const BioImageProcessingState({
    this.status = BioImageProcessingStatus.idle,
    this.totalCount = 0,
    this.completedCount = 0,
    this.errorMessage,
  });
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Watches all bio media attachments for the given [memberId].
/// Uses a Drift stream query so it reactively updates when records are
/// inserted, updated, or soft-deleted.
final bioMediaForMemberProvider =
    StreamProvider.autoDispose.family<List<MediaAttachment>, String>(
  (ref, memberId) {
    final repo = ref.watch(mediaAttachmentRepositoryProvider);
    return repo.watchForMember(memberId);
  },
);

/// Watches the image library — all media_attachments with a non-empty tag.
/// These are user-uploaded images that can be referenced from any member's
/// bio via `![alt](tag)` markdown syntax.
final imageLibraryProvider =
    StreamProvider.autoDispose<List<MediaAttachment>>((ref) {
  final repo = ref.watch(mediaAttachmentRepositoryProvider);
  return repo.watchLibraryImages();
});

/// A version stamp for the image library that changes whenever an image is
/// added, removed, retagged, or replaced (tag + mediaId identity). Folded into
/// markdown render keys so cached parses re-run when the (async) library loads
/// or an image changes. Computed once and shared across all consumers.
final imageLibraryVersionProvider = Provider.autoDispose<int>((ref) {
  final library = ref.watch(imageLibraryProvider).value ?? const [];
  return Object.hashAll(library.map((a) => '${a.tag}:${a.mediaId}'));
});

/// Tracks the in-progress state of a bio-image processing operation.
class BioImageProcessingStateNotifier
    extends Notifier<BioImageProcessingState> {
  @override
  BioImageProcessingState build() => const BioImageProcessingState();

  void setProcessing(int total) {
    state = BioImageProcessingState(
      status: BioImageProcessingStatus.processing,
      totalCount: total,
      completedCount: 0,
    );
  }

  void incrementCompleted() {
    state = BioImageProcessingState(
      status: state.completedCount + 1 >= state.totalCount
          ? BioImageProcessingStatus.done
          : BioImageProcessingStatus.processing,
      totalCount: state.totalCount,
      completedCount: state.completedCount + 1,
    );
  }

  void setError(String message) {
    state = BioImageProcessingState(
      status: BioImageProcessingStatus.error,
      totalCount: state.totalCount,
      completedCount: state.completedCount,
      errorMessage: message,
    );
  }

  void reset() => state = const BioImageProcessingState();
}

final bioImageProcessingStateProvider = NotifierProvider.autoDispose<
    BioImageProcessingStateNotifier, BioImageProcessingState>(
  BioImageProcessingStateNotifier.new,
);

/// Provides a [BioImageProcessor] scoped to a single editor session, keyed by
/// a session id the host editor generates in `initState`.
///
/// Per-session (rather than one global instance) is deliberate:
///   - The host editor `State` keeps its session alive by watching this for its
///     whole lifetime, so a staged image can't be discarded before the save
///     flow calls `commitStaged()` — even across preview toggles or when the
///     image button unmounts. `autoDispose` then discards staged images exactly
///     when the editor closes (the only watcher goes away).
///   - Two editors open at once get isolated instances, so cancelling/saving
///     one never commits or discards the other's staged images.
final bioImageProcessorProvider =
    Provider.autoDispose.family<BioImageProcessor, String>((ref, sessionId) {
  final mediaService = ref.watch(mediaServiceProvider);
  final repo =
      ref.watch(mediaAttachmentRepositoryProvider) as DriftMediaAttachmentRepository;
  final processor = BioImageProcessor(
    mediaService: mediaService,
    repository: repo,
  );
  ref.onDispose(processor.discardStaged);
  return processor;
});
