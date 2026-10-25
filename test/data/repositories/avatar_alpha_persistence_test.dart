import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase;
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';
import 'package:prism_plurality/shared/utils/avatar_image_picker.dart';
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';

import '../../features/pluralport/harness.dart' as harness;

const _memberId = '10000000-0000-4000-8000-000000000001';
const _groupId = '10000000-0000-4000-8000-000000000002';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File databaseFile;
  late AppDatabase db;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('prism-avatar-alpha-');
    databaseFile = File('${directory.path}/avatars.sqlite');
    db = AppDatabase(NativeDatabase(databaseFile));
    // Synthetic pairing-state flag only: no credentials or native handle exist.
    syncCurrentHandle.value = null;
    syncCredentialsPersisted.value = true;
    SyncRecordMixin.installOutboxRuntime();
  });

  tearDown(() async {
    SyncRecordMixin.installOutboxRuntime();
    syncCredentialsPersisted.value = false;
    syncCurrentHandle.value = null;
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'member alpha survives saves, queued patch and file database reopen',
    () async {
      var members = DriftMemberRepository(db.membersDao, null);
      await members.createMember(
        Member(
          id: _memberId,
          name: 'Synthetic member',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final cropped = _avatarBytes();
      await members.updateMember(
        (await members.getMemberById(
          _memberId,
        ))!.copyWith(avatarImageData: cropped),
      );
      final saved = (await members.getMemberById(_memberId))!.avatarImageData!;
      _expectAlpha(saved);
      final operations = await db.syncOutboxDao.allInIdOrder();
      final avatarPatch = operations.singleWhere(
        (op) =>
            op.entityTable == 'members' &&
            op.entityId == _memberId &&
            op.opType == 'update',
      );
      final fields = jsonDecode(avatarPatch.fieldsJson) as Map<String, dynamic>;
      expect(base64Decode(fields['avatar_image_data'] as String), saved);

      for (var i = 0; i < 3; i++) {
        final current = (await members.getMemberById(_memberId))!;
        await members.updateMember(current.copyWith(name: 'Edited member $i'));
        expect(
          (await members.getMemberById(_memberId))!.avatarImageData,
          saved,
        );
      }
      for (final op in (await db.syncOutboxDao.allInIdOrder()).where(
        (op) => op.entityTable == 'members' && op.id > avatarPatch.id,
      )) {
        expect(
          (jsonDecode(op.fieldsJson) as Map).containsKey('avatar_image_data'),
          isFalse,
        );
      }

      await db.close();
      db = AppDatabase(NativeDatabase(databaseFile));
      members = DriftMemberRepository(db.membersDao, null);
      final reopened = (await members.getMemberById(
        _memberId,
      ))!.avatarImageData!;
      expect(reopened, saved);
      _expectAlpha(reopened);
      final reopenedPatch = (await db.syncOutboxDao.allInIdOrder()).singleWhere(
        (op) => op.id == avatarPatch.id,
      );
      expect(reopenedPatch.fieldsJson, avatarPatch.fieldsJson);
    },
  );

  test(
    'group alpha survives saves, queued patch and file database reopen',
    () async {
      var groups = DriftMemberGroupsRepository(db.memberGroupsDao, null);
      await groups.createGroup(
        MemberGroup(
          id: _groupId,
          name: 'Synthetic group',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await groups.updateGroup(
        (await groups.getAllGroups()).single.copyWith(
          avatarImageData: _avatarBytes(red: 60),
        ),
      );
      final saved = (await groups.getAllGroups()).single.avatarImageData!;
      _expectAlpha(saved);
      final avatarPatch = (await db.syncOutboxDao.allInIdOrder()).singleWhere(
        (op) =>
            op.entityTable == 'member_groups' &&
            op.entityId == _groupId &&
            op.opType == 'update',
      );
      final fields = jsonDecode(avatarPatch.fieldsJson) as Map<String, dynamic>;
      expect(base64Decode(fields['avatar_image_data'] as String), saved);

      for (var i = 0; i < 3; i++) {
        final current = (await groups.getAllGroups()).single;
        await groups.updateGroup(current.copyWith(name: 'Edited group $i'));
        expect((await groups.getAllGroups()).single.avatarImageData, saved);
      }
      for (final op in (await db.syncOutboxDao.allInIdOrder()).where(
        (op) => op.entityTable == 'member_groups' && op.id > avatarPatch.id,
      )) {
        expect(
          (jsonDecode(op.fieldsJson) as Map).containsKey('avatar_image_data'),
          isFalse,
        );
      }

      await db.close();
      db = AppDatabase(NativeDatabase(databaseFile));
      groups = DriftMemberGroupsRepository(db.memberGroupsDao, null);
      final reopened = (await groups.getAllGroups()).single.avatarImageData!;
      expect(reopened, saved);
      _expectAlpha(reopened);
      final reopenedPatch = (await db.syncOutboxDao.allInIdOrder()).singleWhere(
        (op) => op.id == avatarPatch.id,
      );
      expect(reopenedPatch.fieldsJson, avatarPatch.fieldsJson);
    },
  );

  for (final portable in [false, true]) {
    test(
      'member and group alpha survive separate database ${portable ? 'PluralPort ZIP' : 'native JSON'} restore',
      () async {
        final memberAvatar = _avatarBytes();
        final groupAvatar = _avatarBytes(red: 60);
        await DriftMemberRepository(db.membersDao, null).createMember(
          Member(
            id: _memberId,
            name: 'Synthetic member',
            createdAt: DateTime.utc(2026, 1, 1),
            avatarImageData: memberAvatar,
          ),
        );
        await DriftMemberGroupsRepository(db.memberGroupsDao, null).createGroup(
          MemberGroup(
            id: _groupId,
            name: 'Synthetic group',
            createdAt: DateTime.utc(2026, 1, 1),
            avatarImageData: groupAvatar,
          ),
        );
        final destination = AppDatabase(
          NativeDatabase(File('${directory.path}/restored.sqlite')),
        );
        try {
          if (portable) {
            PluralPortService service(AppDatabase database) =>
                PluralPortService(
                  db: database,
                  exporter: harness.makeExport(database),
                  importer: harness.makeImport(
                    database,
                    supportDirectory: directory,
                  ),
                  supportDirectory: () async => directory,
                );
            final bundle = await service(db).exportBundle();
            final decoded = PluralPortBundle.decode(bundle.encode());
            for (final collection in ['members', 'groups']) {
              final row = PluralPortMapper.rows(
                decoded.envelope,
                collection,
              ).single;
              final asset = PluralPortMapper.rows(
                decoded.envelope,
                'assets',
              ).singleWhere((asset) => asset['id'] == row['avatar_asset_id']);
              final bytes = decoded.assetBytes(asset)!;
              expect(
                bytes,
                collection == 'members' ? memberAvatar : groupAvatar,
              );
              _expectAlpha(bytes);
              // Avatar assets need no MIME hint: PNG signatures carry the format.
              expect(asset['mime_type'], isNot('image/jpeg'));
            }
            await service(
              destination,
            ).importPlan(PluralPortMapper.plan(decoded));
          } else {
            final exported = await harness.makeExport(db).buildExport();
            await harness
                .makeImport(destination, supportDirectory: directory)
                .importData(jsonEncode(exported.toJson()));
          }
          final restoredMember = (await DriftMemberRepository(
            destination.membersDao,
            null,
          ).getAllMembers()).single;
          final restoredGroup = (await DriftMemberGroupsRepository(
            destination.memberGroupsDao,
            null,
          ).getAllGroups()).single;
          expect(restoredMember.avatarImageData, memberAvatar);
          expect(restoredGroup.avatarImageData, groupAvatar);
          _expectAlpha(restoredMember.avatarImageData!);
          _expectAlpha(restoredGroup.avatarImageData!);
        } finally {
          await destination.close();
        }
      },
    );
  }
}

Uint8List _avatarBytes({int red = 40}) {
  final image = img.Image(width: 24, height: 24, numChannels: 4);
  for (final pixel in image) {
    pixel.setRgba(red, 100, 180, [0, 128, 255][pixel.x ~/ 8]);
  }
  return encodeAvatarOutputForStorage(Uint8List.fromList(img.encodePng(image)));
}

void _expectAlpha(Uint8List bytes) {
  expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  expect(bytes.length, lessThanOrEqualTo(AvatarNormalizer.targetMaxBytes));
  final image = img.decodePng(bytes)!;
  expect(image.width, 24);
  expect(image.height, 24);
  expect(image.getPixel(4, 12).a, 0);
  expect(image.getPixel(12, 12).a, 128);
  expect(image.getPixel(20, 12).a, 255);
}
