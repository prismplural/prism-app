import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/services/media/image_compression_service.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/media_service.dart';
import 'package:prism_plurality/data/repositories/drift_media_attachment_repository.dart';
import 'package:prism_plurality/features/members/services/bio_image_importer.dart';

import '../../helpers/bio_image_test_utils.dart';

void main() {
  group('BioImageImporter', () {
    late TestBioImageInfra infra;
    late DriftMediaAttachmentRepository repository;
    late _FakeBioMediaService mediaService;

    setUp(() {
      infra = TestBioImageInfra.create();
      repository = DriftMediaAttachmentRepository(
        infra.database.mediaAttachmentsDao,
        null,
      );
      mediaService = _FakeBioMediaService(infra);
    });

    tearDown(() => infra.close());

    test(
      'imports URL-like markdown image refs with the shared parser',
      () async {
        final fetched = <String>[];
        final importer = BioImageImporter(
          mediaService: mediaService,
          repository: repository,
          fetchImageBytes: (url, {int maxBytes = 5 * 1024 * 1024}) async {
            fetched.add(url);
            return _bytesFor(url);
          },
        );

        const markdown =
            '![Blinkie](i.postimg.cc/abc/blinkie.gif#50%) '
            '![Stamp](//cdn.example.com/stamp.png "A stamp") '
            '![Remote](HTTPS://cdn.example.com/remote.png)';

        final rewritten = await importer.processBio(markdown);

        expect(fetched, [
          'i.postimg.cc/abc/blinkie.gif',
          '//cdn.example.com/stamp.png',
          'HTTPS://cdn.example.com/remote.png',
        ]);
        expect(rewritten, isNot(contains('i.postimg.cc')));
        expect(rewritten, isNot(contains('//cdn.example.com/stamp.png')));
        expect(
          rewritten,
          isNot(contains('HTTPS://cdn.example.com/remote.png')),
        );
        expect(rewritten, contains('#50%'));
        expect(rewritten, contains('"A stamp"'));
        expect(importer.importedCount, 3);
        expect(mediaService.uploadedMediaIds, hasLength(3));

        final attachments = await repository.getForMember('');
        expect(attachments, hasLength(3));
        expect(
          attachments.map((attachment) => attachment.sourceUrl),
          containsAll([
            'i.postimg.cc/abc/blinkie.gif',
            '//cdn.example.com/stamp.png',
            'HTTPS://cdn.example.com/remote.png',
          ]),
        );
        for (final attachment in attachments) {
          expect(rewritten, contains('](${attachment.tag}'));
        }
      },
    );

    test(
      'leaves failed URLs untouched and dedupes repeated successes',
      () async {
        final fetched = <String>[];
        final importer = BioImageImporter(
          mediaService: mediaService,
          repository: repository,
          fetchImageBytes: (url, {int maxBytes = 5 * 1024 * 1024}) async {
            fetched.add(url);
            if (url.contains('missing')) return null;
            return _bytesFor(url);
          },
        );

        const okUrl = 'https://cdn.example.com/ok.png';
        const missingUrl = 'http://example.com/missing.png';
        const markdown =
            '![One]($okUrl) ![Two]($okUrl#2em) ![Missing]($missingUrl)';

        final rewritten = await importer.processBio(markdown);
        final attachments = await repository.getForMember('');

        expect(fetched, [okUrl, missingUrl]);
        expect(attachments, hasLength(1));
        expect(importer.importedCount, 1);
        final tag = attachments.single.tag;
        expect(
          rewritten,
          '![One]($tag) ![Two]($tag#2em) ![Missing]($missingUrl)',
        );
      },
    );
  });
}

Uint8List _bytesFor(String value) {
  final codeUnits = value.codeUnits;
  return Uint8List.fromList([
    codeUnits.length & 0xff,
    for (final codeUnit in codeUnits.take(8)) codeUnit & 0xff,
  ]);
}

class _FakeBioMediaService extends MediaService {
  _FakeBioMediaService(TestBioImageInfra infra)
    : super(
        compression: ImageCompressionService(),
        encryption: MediaEncryptionService(),
        uploadQueue: infra.uploadQueue,
        downloadManager: infra.downloadManager,
      );

  final uploadedMediaIds = <String>[];
  var _nextMediaId = 0;

  @override
  Future<MediaAttachmentData> prepareBioImage(Uint8List imageBytes) async {
    final mediaId = 'media-${_nextMediaId++}';
    final fingerprint = imageBytes.join('-');
    return MediaAttachmentData(
      mediaId: mediaId,
      thumbnailMediaId: '',
      encryptedImage: Uint8List.fromList(imageBytes),
      encryptedThumbnail: Uint8List(0),
      encryptionKey: Uint8List.fromList(const [1, 2, 3]),
      contentHash: 'content-$fingerprint',
      plaintextHash: 'plain-$fingerprint',
      thumbnailContentHash: '',
      thumbnailPlaintextHash: '',
      width: 1,
      height: 1,
      sizeBytes: imageBytes.length,
      blurhash: '',
      mimeType: 'image/png',
    );
  }

  @override
  Future<void> uploadBioImage(MediaAttachmentData data) async {
    uploadedMediaIds.add(data.mediaId);
  }
}
