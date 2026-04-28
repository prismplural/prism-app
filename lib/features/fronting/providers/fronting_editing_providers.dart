import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_change_executor.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_edit_guard.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_service.dart';

/// Provides a stateless [FrontingEditGuard] for validating session edits
/// before they are committed.
final frontingEditGuardProvider = Provider<FrontingEditGuard>((ref) {
  return const FrontingEditGuard();
});

/// Provides a stateless [FrontingEditResolutionService] for computing the
/// changes needed to resolve overlaps, gaps, and deletes.
final frontingEditResolutionServiceProvider =
    Provider<FrontingEditResolutionService>((ref) {
  return const FrontingEditResolutionService();
});

/// Provides a [FrontingChangeExecutor] wired to the fronting session
/// repository and a [MutationRunner] backed by the app database.
final frontingChangeExecutorProvider = Provider<FrontingChangeExecutor>((ref) {
  final repository = ref.watch(frontingSessionRepositoryProvider);
  final mutationRunner = MutationRunner.forDatabase(ref.watch(databaseProvider));
  return FrontingChangeExecutor(
    repository: repository,
    mutationRunner: mutationRunner,
    // Required so convertToUnknown / gap-fill writes that target the
    // Unknown sentinel id can lazily create the sentinel member before
    // the foreign key resolves.
    memberRepository: ref.watch(memberRepositoryProvider),
  );
});
