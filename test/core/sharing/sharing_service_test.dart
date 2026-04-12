import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sharing/share_invite.dart';
import 'package:prism_plurality/core/sharing/sharing_service.dart';
import 'package:prism_plurality/core/sharing/sharing_sync_api.dart';
import 'package:prism_plurality/domain/models/friend_record.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/friends_repository.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import '../../helpers/fake_repositories.dart';

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFriendsRepository implements FriendsRepository {
  @override
  Future<void> createFriend(FriendRecord friend) async {}

  @override
  Future<void> deleteFriend(String id) async {}

  @override
  Future<FriendRecord?> getById(String id) async => null;

  @override
  Future<void> updateFriend(FriendRecord friend) async {}

  @override
  Stream<List<FriendRecord>> watchAll() => Stream.value(const []);
}

class _FakeSharingSyncApi extends SharingSyncApi {
  _EnableCall? enableCall;
  _DisableCall? disableCall;
  final List<_EnsurePrekeyCall> ensurePrekeyCalls = [];
  _ChangePasswordCall? changePasswordCall;
  int persistCallCount = 0;
  int persistPasswordChangeCallCount = 0;
  String nextSharingId = 'generated-sharing-id';
  int nextIdentityGeneration = 0;

  @override
  Future<String> sharingEnable({
    required ffi.PrismSyncHandle handle,
    String? currentSharingId,
    required int identityGeneration,
  }) async {
    enableCall = _EnableCall(
      currentSharingId: currentSharingId,
      identityGeneration: identityGeneration,
    );
    return nextSharingId;
  }

  @override
  Future<void> sharingDisable({
    required ffi.PrismSyncHandle handle,
    required String sharingId,
  }) async {
    disableCall = _DisableCall(sharingId: sharingId);
  }

  @override
  Future<void> sharingEnsurePrekey({
    required ffi.PrismSyncHandle handle,
    required String sharingId,
    required int identityGeneration,
  }) async {
    ensurePrekeyCalls.add(
      _EnsurePrekeyCall(
        sharingId: sharingId,
        identityGeneration: identityGeneration,
      ),
    );
  }

  @override
  Future<String> sharingInitiate({
    required ffi.PrismSyncHandle handle,
    required String senderSharingId,
    required String recipientSharingId,
    required String displayName,
    required String offeredScopes,
    required int identityGeneration,
  }) => throw UnimplementedError();

  @override
  Future<String> sharingProcessPending({
    required ffi.PrismSyncHandle handle,
    required String recipientSharingId,
    required String existingRelationshipsJson,
    required String seenInitIdsJson,
    required int identityGeneration,
  }) => throw UnimplementedError();

  @override
  Future<int> changePassword({
    required ffi.PrismSyncHandle handle,
    required String oldPassword,
    required String newPassword,
    required List<int> secretKey,
    String? sharingId,
    required int currentIdentityGeneration,
  }) async {
    changePasswordCall = _ChangePasswordCall(
      oldPassword: oldPassword,
      newPassword: newPassword,
      secretKey: List<int>.from(secretKey),
      sharingId: sharingId,
      currentIdentityGeneration: currentIdentityGeneration,
    );
    return nextIdentityGeneration;
  }

  @override
  Future<void> persistPasswordChangeState({
    required ffi.PrismSyncHandle handle,
    required AppDatabase db,
  }) async {
    persistPasswordChangeCallCount += 1;
  }

  @override
  Future<void> persistState({required ffi.PrismSyncHandle handle}) async {
    persistCallCount += 1;
  }
}

class _EnableCall {
  const _EnableCall({
    required this.currentSharingId,
    required this.identityGeneration,
  });

  final String? currentSharingId;
  final int identityGeneration;
}

class _DisableCall {
  const _DisableCall({required this.sharingId});

  final String sharingId;
}

class _EnsurePrekeyCall {
  const _EnsurePrekeyCall({
    required this.sharingId,
    required this.identityGeneration,
  });

  final String sharingId;
  final int identityGeneration;
}

class _ChangePasswordCall {
  const _ChangePasswordCall({
    required this.oldPassword,
    required this.newPassword,
    required this.secretKey,
    required this.sharingId,
    required this.currentIdentityGeneration,
  });

  final String oldPassword;
  final String newPassword;
  final List<int> secretKey;
  final String? sharingId;
  final int currentIdentityGeneration;
}

void main() {
  late AppDatabase db;
  late FakeSystemSettingsRepository settingsRepository;
  late _FakeSharingSyncApi sharingApi;
  late SharingService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settingsRepository = FakeSystemSettingsRepository();
    sharingApi = _FakeSharingSyncApi();
    service = SharingService(
      handle: const _FakePrismSyncHandle(),
      settingsRepository: settingsRepository,
      friendsRepository: _FakeFriendsRepository(),
      sharingRequestsDao: db.sharingRequestsDao,
      sharingApi: sharingApi,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'disableSharing preserves synced sharingId for future re-enable',
    () async {
      settingsRepository.settings = const SystemSettings(
        sharingId: 'sharing-123',
        identityGeneration: 7,
      );

      await service.disableSharing();

      expect(sharingApi.disableCall?.sharingId, 'sharing-123');
      expect(settingsRepository.settings.sharingId, 'sharing-123');
      expect(settingsRepository.settings.identityGeneration, 7);
      expect(sharingApi.persistCallCount, 1);
    },
  );

  test(
    'createInvite threads current sharing identity state through enable path',
    () async {
      settingsRepository.settings = const SystemSettings(
        sharingId: 'sharing-123',
        identityGeneration: 9,
      );
      sharingApi.nextSharingId = 'sharing-123';

      final invite = await service.createInvite(displayName: '  Alice  ');

      expect(invite, isA<ShareInvite>());
      expect(invite.sharingId, 'sharing-123');
      expect(invite.displayName, 'Alice');
      expect(sharingApi.enableCall?.currentSharingId, 'sharing-123');
      expect(sharingApi.enableCall?.identityGeneration, 9);
      expect(sharingApi.ensurePrekeyCalls, hasLength(1));
      expect(sharingApi.ensurePrekeyCalls.single.sharingId, 'sharing-123');
      expect(sharingApi.ensurePrekeyCalls.single.identityGeneration, 9);
      expect(settingsRepository.settings.sharingId, 'sharing-123');
      expect(settingsRepository.settings.identityGeneration, 9);
      expect(sharingApi.persistCallCount, 1);
    },
  );

  test(
    'createInvite persists a newly issued sharingId without changing generation',
    () async {
      settingsRepository.settings = const SystemSettings(identityGeneration: 4);
      sharingApi.nextSharingId = 'sharing-new';

      final invite = await service.createInvite();

      expect(invite.sharingId, 'sharing-new');
      expect(settingsRepository.settings.sharingId, 'sharing-new');
      expect(settingsRepository.settings.identityGeneration, 4);
      expect(sharingApi.enableCall?.currentSharingId, isNull);
      expect(sharingApi.enableCall?.identityGeneration, 4);
      expect(sharingApi.ensurePrekeyCalls.single.sharingId, 'sharing-new');
      expect(sharingApi.ensurePrekeyCalls.single.identityGeneration, 4);
    },
  );

  test('changePassword advances identity generation and preserves sharing id', () async {
    settingsRepository.settings = const SystemSettings(
      sharingId: 'sharing-123',
      identityGeneration: 4,
    );
    sharingApi.nextIdentityGeneration = 5;

    final nextGeneration = await service.changePassword(
      oldPassword: 'old-password',
      newPassword: 'new-password',
      secretKey: const [1, 2, 3, 4],
      db: db,
    );

    expect(nextGeneration, 5);
    expect(sharingApi.changePasswordCall, isNotNull);
    expect(sharingApi.changePasswordCall?.oldPassword, 'old-password');
    expect(sharingApi.changePasswordCall?.newPassword, 'new-password');
    expect(sharingApi.changePasswordCall?.secretKey, const [1, 2, 3, 4]);
    expect(sharingApi.changePasswordCall?.sharingId, 'sharing-123');
    expect(sharingApi.changePasswordCall?.currentIdentityGeneration, 4);
    expect(settingsRepository.settings.identityGeneration, 5);
    expect(settingsRepository.settings.sharingId, 'sharing-123');
    expect(sharingApi.persistPasswordChangeCallCount, 1);
  });
}
