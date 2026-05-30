import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/sp_import_dao.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

/// Summary of what [SpCreationDateBackfillService.preview] found.
class SpCreationDateBackfillPreview {
  const SpCreationDateBackfillPreview({
    required this.matches,
    required this.unmatchedCount,
  });

  /// Members whose `createdAt` will be updated.
  final List<SpCreationDateMatch> matches;

  /// Number of SP members that could not be matched to a Prism member
  /// (no mapping row, null ObjectId timestamp, or member deleted).
  final int unmatchedCount;
}

/// One matched SP member whose creation date will be backfilled.
class SpCreationDateMatch {
  const SpCreationDateMatch({
    required this.prismId,
    required this.memberName,
    required this.currentCreatedAt,
    required this.newCreatedAt,
  });

  final String prismId;
  final String memberName;
  final DateTime currentCreatedAt;
  final DateTime newCreatedAt;
}

/// Two-phase service that backfills member `createdAt` timestamps from the
/// MongoDB ObjectId timestamps embedded in a SimplePlural export.
///
/// Phase 1 – [preview]: dry-run that returns what will change.
/// Phase 2 – [apply]:   writes the changes inside a single transaction.
///
/// The service does NOT extend or depend on [SpImporter]; it uses the
/// [SpImportDao] to resolve SP→Prism ID mappings that the importer already
/// wrote into `sp_id_map`.
class SpCreationDateBackfillService {
  SpCreationDateBackfillService({
    required AppDatabase db,
    required SpImportDao spImportDao,
    required MemberRepository memberRepo,
  }) : _db = db,
       _spImportDao = spImportDao,
       _memberRepo = memberRepo;

  final AppDatabase _db;
  final SpImportDao _spImportDao;
  final MemberRepository _memberRepo;

  /// Compute what would change if [apply] were called with [export].
  ///
  /// Steps:
  /// 1. Load all SP→Prism ID mappings; keep only `entityType == 'member'`.
  /// 2. For each SP member in [export]:
  ///    a. Extract the ObjectId timestamp; skip if null.
  ///    b. Look up the Prism member ID; skip if no mapping.
  ///    c. Load the current Prism member; skip if deleted/missing.
  ///    d. Collect a [SpCreationDateMatch].
  Future<SpCreationDateBackfillPreview> preview(SpExportData export) async {
    // Step 1 – build spId → prismId lookup for member mappings.
    final allMappings = await _spImportDao.getAllMappings();
    final memberIdMap = <String, String>{
      for (final row in allMappings)
        if (row.entityType == 'member') row.spId: row.prismId,
    };

    final matches = <SpCreationDateMatch>[];
    var unmatchedCount = 0;

    // Step 2 – walk every SP member in the export.
    for (final spMember in export.members) {
      // 2a. Extract ObjectId timestamp.
      final newCreatedAt = extractObjectIdTimestamp(spMember.id);
      if (newCreatedAt == null) {
        unmatchedCount++;
        continue;
      }

      // 2b. Look up Prism member ID.
      final prismId = memberIdMap[spMember.id];
      if (prismId == null) {
        unmatchedCount++;
        continue;
      }

      // 2c. Load current member (may have been deleted since import).
      final member = await _memberRepo.getMemberById(prismId);
      if (member == null) {
        unmatchedCount++;
        continue;
      }

      // 2d. Record the match.
      matches.add(
        SpCreationDateMatch(
          prismId: prismId,
          memberName: member.name,
          currentCreatedAt: member.createdAt,
          newCreatedAt: newCreatedAt,
        ),
      );
    }

    return SpCreationDateBackfillPreview(
      matches: matches,
      unmatchedCount: unmatchedCount,
    );
  }

  /// Apply the changes described in [preview].
  ///
  /// All writes are wrapped in a single transaction. Re-running is naturally
  /// idempotent because [MemberRepository.updateMemberFields] diffs against
  /// the stored row and only emits CRDT ops for values that actually changed.
  ///
  /// Returns the number of members updated.
  Future<int> apply(SpCreationDateBackfillPreview preview) async {
    await _db.transaction(() async {
      for (final match in preview.matches) {
        await _memberRepo.updateMemberFields(match.prismId, {
          'created_at': match.newCreatedAt,
        });
      }
    });
    return preview.matches.length;
  }
}
