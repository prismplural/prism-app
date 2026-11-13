import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:prism_media_codec/prism_media_codec.dart' as media_codec;
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/features/data_management/providers/data_management_providers.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';
import 'package:prism_plurality/features/pluralport/views/pluralport_sheet.dart';
import '../features/pluralport/harness.dart';
import 'e2e_fixture.dart';
import 'e2e_support.dart';

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var syncInitialized = false;
  var codecInitialized = false;
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
    syncInitialized = true;
    final manifestFile = File(
      'build/native_assets/${Platform.operatingSystem}/native_assets.json',
    );
    if (!manifestFile.existsSync()) {
      throw StateError(
        'Media codec native assets were not built: ${manifestFile.path}. Native E2E requires the real codec; run through flutter test with native assets enabled.',
      );
    }
    final target = switch (Abi.current()) {
      Abi.macosArm64 => 'macos_arm64',
      Abi.macosX64 => 'macos_x64',
      Abi.linuxArm64 => 'linux_arm64',
      Abi.linuxX64 => 'linux_x64',
      _ => throw UnsupportedError(
        'Unsupported native E2E host ABI: ${Abi.current()}',
      ),
    };
    final manifest = jsonDecode(await manifestFile.readAsString()) as Map;
    final assets = (manifest['native-assets'] as Map)[target] as Map?;
    final codec =
        assets?['package:prism_media_codec/generated/frb_generated.dart']
            as List?;
    if (codec == null ||
        codec.length != 2 ||
        codec.first != 'absolute' ||
        codec.last is! String) {
      throw StateError(
        'Absolute media codec native asset missing for $target in ${manifestFile.path}',
      );
    }
    await media_codec.MediaCodecRustLib.init(
      externalLibrary: ExternalLibrary.open(codec.last as String),
    );
    codecInitialized = true;
  });
  tearDownAll(() {
    if (codecInitialized) media_codec.MediaCodecRustLib.dispose();
    if (syncInitialized) RustLib.dispose();
  });

  for (final scenario in ['available', 'not-found', 'integrity-failure']) {
    test(
      'production export provider handles relay-only media: $scenario',
      skip: e2eSkip(),
      timeout: const Timeout(Duration(minutes: 2)),
      () async {
        final relay = await spawnRelay();
        E2EDevice? a, b;
        AppDatabase? db;
        ProviderContainer? container;
        DownloadManager? downloads;
        StreamSubscription<DownloadProgress>? downloadProgress;
        Directory? dir;
        final previousPaths = PathProviderPlatform.instance;
        try {
          a = await createDevice(relay);
          final image = img.Image(width: 64, height: 64);
          for (var y = 0; y < 64; y++) {
            for (var x = 0; x < 64; x++) {
              image.setPixelRgb(x, y, x * 3, y * 3, 80);
            }
          }
          final original = Uint8List.fromList(img.encodePng(image));
          final encryption = MediaEncryptionService();
          final encrypted = await encryption.encryptMedia(original);
          const mediaId = 'pluralport-relay-original';
          const attachmentId = 'pluralport-relay-attachment';
          if (scenario != 'not-found') {
            await ffi.uploadMedia(
              handle: a.handle,
              mediaId: mediaId,
              contentHash: encrypted.ciphertextHash,
              data: encrypted.ciphertext,
              pairingPush: false,
            );
          }
          final fields = <String, dynamic>{
            'media_id': mediaId,
            'media_type': 'image',
            'encryption_key_b64': base64Encode(encrypted.key),
            'content_hash': encrypted.ciphertextHash,
            'plaintext_hash': scenario == 'integrity-failure'
                ? '0' * 64
                : encrypted.plaintextHash,
            'mime_type': 'image/png',
            'size_bytes': original.length,
            'width': 64,
            'height': 64,
            'thumbnail_media_id': 'legacy-relay-thumb',
            'thumbnail_content_hash': '',
            'thumbnail_plaintext_hash': '',
          };
          await ffi.recordCreate(
            handle: a.handle,
            table: 'media_attachments',
            entityId: attachmentId,
            fieldsJson: jsonEncode(fields),
          );
          b = await pairNewDevice(relay, a);
          // Project only the reference received by pairing into the app database.
          final received = <String, dynamic>{};
          for (final field in fields.keys) {
            final raw = await ffi.readFieldValue(
              handle: b.handle,
              table: 'media_attachments',
              entityId: attachmentId,
              field: field,
            );
            expect(
              raw,
              isNotNull,
              reason: 'paired reference must contain $field',
            );
            received[field] = jsonDecode(raw!);
          }
          expect(received, fields);
          dir = await Directory.systemTemp.createTemp('pluralport-real-relay-');
          PathProviderPlatform.instance = _TemporaryPaths(dir.path);
          final cache = await Directory('${dir.path}/prism_media').create();
          db = makeDb();
          await db.mediaAttachmentsDao.insertAttachment(
            MediaAttachmentsCompanion.insert(
              id: attachmentId,
              mediaId: drift.Value(received['media_id'] as String),
              mediaType: const drift.Value('image'),
              encryptionKeyB64: drift.Value(
                received['encryption_key_b64'] as String,
              ),
              contentHash: drift.Value(received['content_hash'] as String),
              plaintextHash: drift.Value(received['plaintext_hash'] as String),
              mimeType: const drift.Value('image/png'),
              sizeBytes: drift.Value(original.length),
              width: const drift.Value(64),
              height: const drift.Value(64),
              thumbnailMediaId: const drift.Value('legacy-relay-thumb'),
            ),
          );
          final before = [
            for (final r in await db.mediaAttachmentsDao.getAll()) r.toJson(),
          ];
          downloads = DownloadManager(
            handle: b.handle,
            encryption: encryption,
            cacheDirOverride: cache,
          );
          var actualDownloadAttempts = 0;
          downloadProgress = downloads.progressStream(mediaId).listen((
            progress,
          ) {
            if (progress.state == DownloadState.downloading) {
              actualDownloadAttempts++;
            }
          });
          expect(await downloads.isCached(mediaId), isFalse);
          expect(await cache.list().isEmpty, isTrue);
          container = ProviderContainer(
            overrides: [
              databaseProvider.overrideWithValue(db),
              dataExportServiceProvider.overrideWithValue(makeExport(db)),
              dataImportServiceProvider.overrideWithValue(
                makeImport(db, supportDirectory: dir),
              ),
              downloadManagerProvider.overrideWithValue(downloads),
            ],
          );
          // Keep the production recovery callbacks under test.
          final service = container.read(pluralPortServiceProvider);
          final bundle = await service.exportBundle();
          expect(PluralPortService.validateBundle(bundle), isEmpty);
          final preview = PluralPortService.previewBytes(bundle.encode());
          // Missing bytes must not leave broken bundle declarations.
          expect(preview.summary.missingFiles, 0);
          expect([
            for (final r in await db.mediaAttachmentsDao.getAll()) r.toJson(),
          ], before);
          final assets = PluralPortMapper.rows(bundle.envelope, 'assets');
          final originalAsset = assets.singleWhere(
            (asset) =>
                asset['id'] ==
                PluralPortMapper.stableId('prism/media', attachmentId),
          );
          final codes = [
            for (final w in bundle.envelope['warnings'] as List)
              (w as Map)['code'],
          ];
          if (scenario == 'available') {
            expect(bundle.assetBytes(originalAsset), original);
            expect(
              originalAsset['sha256'],
              sha256.convert(original).toString(),
            );
            expect(codes, contains('asset_media_recovered'));
            expect(codes, contains('asset_thumbnail_generated'));
            expect(await downloads.isCached(mediaId), isTrue);
            final thumbs = assets
                .where(
                  (asset) =>
                      asset['id'] != originalAsset['id'] &&
                      asset['bundle_path'] != null,
                )
                .toList();
            expect(thumbs, hasLength(1));
            expect(
              img.decodeImage(bundle.assetBytes(thumbs.single)!),
              isNotNull,
            );
            expect(preview.summary.bundledFiles, bundle.files.length);
            expect(actualDownloadAttempts, 1);
            await File('${cache.path}/$mediaId.enc').delete();
            expect(await downloads.isCached(mediaId), isFalse);
            final afterCacheLoss = await service.exportBundle();
            final recoveredAgain = PluralPortMapper.rows(
              afterCacheLoss.envelope,
              'assets',
            ).singleWhere((asset) => asset['id'] == originalAsset['id']);
            expect(afterCacheLoss.assetBytes(recoveredAgain), original);
            expect(
              PluralPortService.previewBytes(
                afterCacheLoss.encode(),
              ).summary.bundledFiles,
              afterCacheLoss.files.length,
            );
            expect(await downloads.isCached(mediaId), isTrue);
            expect(actualDownloadAttempts, 2);
            expect([
              for (final w in afterCacheLoss.envelope['warnings'] as List)
                (w as Map)['code'],
            ], contains('asset_media_recovered'));
            expect([
              for (final r in await db.mediaAttachmentsDao.getAll()) r.toJson(),
            ], before);
          } else {
            expect(originalAsset['bundle_path'], isNull);
            expect(originalAsset['sha256'], isNull);
            expect(originalAsset['size_bytes'], isNull);
            expect(preview.summary.bundledFiles, 0);
            expect(codes, contains('asset_bundle_missing'));
            final prismExtension =
                (originalAsset['extensions'] as Map)['prism'] as Map;
            final unavailable = prismExtension['unavailable'] as Map;
            // Fresh-download integrity failures are retryable, unlike corrupt cache hits.
            expect(
              unavailable['reason'],
              contains(scenario == 'not-found' ? 'notFound' : 'server'),
            );
            expect(actualDownloadAttempts, 1);
            expect(await downloads.isCached(mediaId), isFalse);
            expect(codes, isNot(contains('asset_media_recovered')));
            expect(codes, isNot(contains('asset_thumbnail_generated')));
          }
        } finally {
          await downloadProgress?.cancel();
          container?.dispose();
          downloads?.dispose();
          await db?.close();
          PathProviderPlatform.instance = previousPaths;
          if (dir != null && await dir.exists()) {
            await dir.delete(recursive: true);
          }
          b?.dispose();
          a?.dispose();
          relay.stop();
        }
      },
    );
  }
}
