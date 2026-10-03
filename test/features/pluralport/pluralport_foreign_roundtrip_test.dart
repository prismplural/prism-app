import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'harness.dart';
import 'complex_fixture.dart';
import 'package:prism_sync/generated/frb_generated.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';

void main() {
  setUpAll(initializeFixtureCrypto);
  tearDownAll(RustLib.dispose);
  test(
    'complex native records survive portable export and database restore',
    () async {
      final source = makeDb();
      final target = makeDb();
      addTearDown(source.close);
      addTearDown(target.close);
      final dir = await Directory.systemTemp.createTemp('pluralport-complex-');
      addTearDown(() => dir.delete(recursive: true));
      final sourceDir = await Directory('${dir.path}/source').create();
      final targetDir = await Directory('${dir.path}/target').create();
      PluralPortService service(db) => PluralPortService(
        db: db,
        exporter: makeExport(db),
        importer: makeImport(
          db,
          supportDirectory: db == source ? sourceDir : targetDir,
        ),
        supportDirectory: () async => db == source ? sourceDir : targetDir,
      );
      final fixture = await complexNativeFixture();
      await makeImport(
        source,
        supportDirectory: sourceDir,
      ).importData(jsonEncode(fixture.native), mediaBlobs: fixture.blobs);
      await service(source).importPlan(PluralPortMapper.plan(opaqueFixture()));
      final original = (await makeExport(source).buildExport()).toJson();
      final outgoing = await service(source).exportBundle();
      final output = Platform.environment['PLURALPORT_OUTPUT'];
      if (output != null) {
        await Directory(output).create(recursive: true);
        await File(
          '$output/prism.pluralport.zip',
        ).writeAsBytes(outgoing.encode());
        await File(
          '$output/prism-native.json',
        ).writeAsString(jsonEncode(original));
        return;
      }
      final foreign = Platform.environment['PLURALPORT_RETURN'];
      final incoming = foreign == null
          ? outgoing
          : PluralPortBundle.decode(await File(foreign).readAsBytes());
      final defaultTarget = makeDb();
      addTearDown(defaultTarget.close);
      await service(defaultTarget).importPlan(PluralPortMapper.plan(incoming));
      final defaultNative = (await makeExport(
        defaultTarget,
      ).buildExport()).toJson();
      expect(defaultNative['appPreferences'] ?? [], isEmpty);
      expect(
        (defaultNative['systemSettings'] as List).first['accentColorHex'],
        isNot('#123456'),
      );
      final preservedOnly = await service(defaultTarget).exportBundle();
      final sourceModules =
          ((incoming.envelope['extensions'] as Map)['prism']
                  as Map)['native_modules']
              as Map;
      final preservedModules =
          ((preservedOnly.envelope['extensions'] as Map)['prism']
                  as Map)['native_modules']
              as Map;
      expect(
        preservedModules['appPreferences'],
        sourceModules['appPreferences'],
      );
      expect(
        preservedModules['systemSettings'],
        sourceModules['systemSettings'],
      );
      await service(target).importPlan(
        PluralPortMapper.plan(incoming),
        importSystemProfile: true,
        restorePrismPreferences: true,
      );
      final restored = (await makeExport(target).buildExport()).toJson();
      final returnedBundle = await service(target).exportBundle();
      expect(
        returnedBundle.envelope['experimental_module'],
        outgoing.envelope['experimental_module'],
      );
      expect(
        (returnedBundle.envelope['extensions'] as Map)['future_fixture'],
        (outgoing.envelope['extensions'] as Map)['future_fixture'],
      );
      for (final entry in outgoing.files.entries) {
        expect(returnedBundle.files[entry.key], entry.value, reason: entry.key);
      }

      final report = Platform.environment['PLURALPORT_REPORT'];
      if (report != null) {
        await File('$report-original.json').writeAsString(jsonEncode(original));
        await File('$report-restored.json').writeAsString(jsonEncode(restored));
      }

      // Connection activation is deliberately excluded from portable restore.
      // Choice values are structured JSON; whitespace is not user content.
      Json comparable(Json input) {
        final copy = PluralPortMapper.clone(input);
        for (final member in PluralPortMapper.rows(copy, 'headmates')) {
          member.remove('pluralkitSyncIgnored');
        }
        final choiceIds = PluralPortMapper.rows(copy, 'customFields')
            .where((r) => r['fieldTypeId'] == 'choice')
            .map((r) => r['id'])
            .toSet();
        for (final value in PluralPortMapper.rows(copy, 'customFieldValues')) {
          if (choiceIds.contains(value['customFieldId'])) {
            value['value'] = jsonDecode(value['value'] as String);
          }
        }
        for (final media in PluralPortMapper.rows(copy, 'mediaAttachments')) {
          for (final key in [
            'mediaId',
            'encryptionKeyB64',
            'contentHash',
            'thumbnailMediaId',
            'thumbnailContentHash',
          ]) {
            media.remove(key);
          }
        }
        return copy;
      }

      final targetMedia = await target.mediaAttachmentsDao.getAll();
      final sourceMedia = await source.mediaAttachmentsDao.getAll();
      final crypto = MediaEncryptionService();
      for (final before in sourceMedia) {
        final after = targetMedia.singleWhere((a) => a.id == before.id);
        if (before.mediaId.isEmpty) continue;
        Future<List<int>> decrypt(
          row,
          Directory directory, {
          bool thumbnail = false,
        }) => crypto.decryptMedia(
          ciphertext: File(
            '${directory.path}/prism_media/${thumbnail ? row.thumbnailMediaId : row.mediaId}.enc',
          ).readAsBytesSync(),
          key: base64Decode(row.encryptionKeyB64),
          expectedCiphertextHash: thumbnail
              ? row.thumbnailContentHash
              : row.contentHash,
          expectedPlaintextHash: thumbnail
              ? row.thumbnailPlaintextHash
              : row.plaintextHash,
        );
        expect(
          await decrypt(after, targetDir),
          await decrypt(before, sourceDir),
          reason: before.id,
        );
        if (before.thumbnailMediaId.isNotEmpty) {
          expect(
            await decrypt(after, targetDir, thumbnail: true),
            await decrypt(before, sourceDir, thumbnail: true),
            reason: '${before.id} thumbnail',
          );
        }
      }
      // A repeated restore must reuse native identities, including duplicate-byte
      // attachment associations, rather than producing a second copy.
      await service(target).importPlan(PluralPortMapper.plan(incoming));
      final repeated = (await makeExport(target).buildExport()).toJson();
      for (final key in [
        ...PluralPortMapper.collections.values,
        ...PluralPortMapper.nativeModuleKeys,
        'mediaAttachments',
      ]) {
        expect(repeated[key], restored[key], reason: 'Repeated import: $key');
      }
      if (Platform.environment['PLURALPORT_MUTATED'] == '1') {
        expect(
          PluralPortMapper.rows(
            restored,
            'headmates',
          ).singleWhere((r) => r['id'] == 'm1')['name'],
          'Alex edited in Sheaf',
        );
        expect(
          PluralPortMapper.rows(
            restored,
            'headmates',
          ).any((r) => r['id'] == 'm3'),
          isFalse,
        );
        expect(
          PluralPortMapper.rows(
            restored,
            'memberGroups',
          ).any((r) => r['id'] == 'g2'),
          isFalse,
        );
        expect(
          PluralPortMapper.rows(
            restored,
            'customFields',
          ).any((r) => r['id'] == 'cf1'),
          isFalse,
        );
        expect(
          PluralPortMapper.rows(
            restored,
            'customFieldValues',
          ).any((r) => r['customFieldId'] == 'cf1'),
          isFalse,
        );
        expect(
          PluralPortMapper.rows(
            restored,
            'headmates',
          ).singleWhere((r) => r['id'] == 'm1')['profilePhotoData'],
          isNotEmpty,
        );
        return;
      }
      final expected = comparable(original);
      final actual = comparable(restored);
      final mismatches = <String>[];
      for (final key in original.keys) {
        if ([
          'exportDate',
          'totalRecords',
          'pluralPortArchives',
          'pluralKitSyncState',
        ].contains(key)) {
          continue;
        }
        if (canonicalJson(expected[key]) != canonicalJson(actual[key])) {
          mismatches.add(key);
        }
      }
      expect(
        mismatches,
        isEmpty,
        reason: 'Native record families changed: $mismatches',
      );
    },
  );
}
