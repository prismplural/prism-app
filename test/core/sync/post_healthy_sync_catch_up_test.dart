import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/migration/services/group_chat_visibility_sync_reemit_service.dart';
import 'package:prism_plurality/features/migration/services/oversized_inline_image_reemit_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_sync_v2_catchup_service.dart';

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'post-healthy catch-up runs the upgrade steps in order',
    () async {
      final calls = <String>[];

      await runPostHealthySyncCatchUp(
        handle: const _FakePrismSyncHandle(),
        db: db,
        failureLabel: 'test catch-up failed',
        onResume: (_) async => calls.add('onResume'),
        reemitGroupChatVisibility: (_, _) async {
          calls.add('groupVisibility');
          return const GroupChatVisibilitySyncReemitResult();
        },
        reemitOversizedInlineImages: (_, _) async {
          calls.add('oversizedImages');
          return const OversizedInlineImageReemitResult();
        },
        repairQuarantinedPushBatches: (_) async => calls.add('repairQuarantine'),
        catchUpPk: (_, _) async {
          calls.add('pkCatchUp');
          return const PkGroupSyncV2CatchupResult();
        },
        drain: (_) async => calls.add('drain'),
      );

      // Nothing was re-normalized, so the repair step is skipped.
      expect(calls, ['onResume', 'groupVisibility', 'oversizedImages', 'pkCatchUp', 'drain']);
    },
  );

  test(
    'repairs quarantined batches only after oversized images were re-normalized',
    () async {
      final calls = <String>[];

      await runPostHealthySyncCatchUp(
        handle: const _FakePrismSyncHandle(),
        db: db,
        failureLabel: 'test catch-up failed',
        onResume: (_) async => calls.add('onResume'),
        reemitGroupChatVisibility: (_, _) async {
          calls.add('groupVisibility');
          return const GroupChatVisibilitySyncReemitResult();
        },
        reemitOversizedInlineImages: (_, _) async {
          calls.add('oversizedImages');
          return const OversizedInlineImageReemitResult(membersRepaired: 1, fieldsReemitted: 1);
        },
        repairQuarantinedPushBatches: (_) async => calls.add('repairQuarantine'),
        catchUpPk: (_, _) async {
          calls.add('pkCatchUp');
          return const PkGroupSyncV2CatchupResult();
        },
        drain: (_) async => calls.add('drain'),
      );

      expect(calls, [
        'onResume',
        'groupVisibility',
        'oversizedImages',
        'repairQuarantine',
        'pkCatchUp',
        'drain',
      ]);
    },
  );

  test(
    'post-healthy catch-up stops and swallows after a failed step',
    () async {
      final calls = <String>[];

      await runPostHealthySyncCatchUp(
        handle: const _FakePrismSyncHandle(),
        db: db,
        failureLabel: 'test catch-up failed',
        onResume: (_) async => calls.add('onResume'),
        reemitGroupChatVisibility: (_, _) async {
          calls.add('groupVisibility');
          throw StateError('boom');
        },
        reemitOversizedInlineImages: (_, _) async {
          calls.add('oversizedImages');
          return const OversizedInlineImageReemitResult();
        },
        repairQuarantinedPushBatches: (_) async => calls.add('repairQuarantine'),
        catchUpPk: (_, _) async {
          calls.add('pkCatchUp');
          return const PkGroupSyncV2CatchupResult();
        },
        drain: (_) async => calls.add('drain'),
      );

      expect(calls, ['onResume', 'groupVisibility']);
    },
  );
}
