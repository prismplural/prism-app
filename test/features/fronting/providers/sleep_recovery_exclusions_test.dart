import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession;
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftFrontingSessionRepository repo;
  late ProviderContainer container;

  FrontingSession sleep(String id) => FrontingSession(
    id: id,
    startTime: DateTime(2026, 3, 10, 22),
    endTime: DateTime(2026, 3, 11, 6),
    sessionType: SessionType.sleep,
  );

  // A bug-era deletion: soft-deleted directly, never through the user delete
  // path, so it was never recorded as intentional.
  Future<void> bugDelete(String id) async {
    await repo.createSession(sleep(id));
    await repo.deleteSession(id);
  }

  // An intentional deletion: through the notifier, which records the exclusion.
  Future<void> userDelete(String id) async {
    await repo.createSession(sleep(id));
    await container.read(sleepNotifierProvider.notifier).deleteSleep(id);
  }

  Future<List<String>> recoverableIds() async {
    final list = await container.read(
      recoverableDeletedSleepSessionsProvider.future,
    );
    return list.map((s) => s.id).toList();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
    final service = FrontingMutationService(
      repository: repo,
      mutationRunner: MutationRunner(transactionRunner: db.transaction),
      frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
        db.frontSessionCommentsDao,
        null,
      ),
    );
    container = ProviderContainer(
      overrides: [frontingMutationServiceProvider.overrideWithValue(service)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'bug-era deletions stay recoverable; intentional ones are excluded',
    () async {
      await bugDelete('bug-a');
      await bugDelete('bug-b');
      await userDelete('intentional');

      expect(await recoverableIds(), unorderedEquals(['bug-a', 'bug-b']));
    },
  );

  test('an intentional deletion never re-pops on a later read', () async {
    await userDelete('x');
    expect(await recoverableIds(), isEmpty);

    container.invalidate(recoverableDeletedSleepSessionsProvider);
    expect(await recoverableIds(), isEmpty);
  });
}
