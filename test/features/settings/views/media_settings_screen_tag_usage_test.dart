import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/settings/views/media_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations_en.dart';

void main() {
  group('tagUsageProvider', () {
    test(
      'does not read Ref after auto-dispose during async usage scan',
      () async {
        final customFieldsRepository = _BlockingCustomFieldsRepository();
        final debugMessages = <String>[];
        final oldDebugPrint = debugPrint;
        debugPrint = (message, {wrapWidth}) {
          if (message != null) debugMessages.add(message);
        };
        addTearDown(() => debugPrint = oldDebugPrint);

        final container = ProviderContainer(
          overrides: [
            imageLibraryProvider.overrideWithValue(
              AsyncValue.data([_libraryAttachment()]),
            ),
            allMembersProvider.overrideWithValue(const AsyncValue.data([])),
            allNotesProvider.overrideWithValue(const AsyncValue.data([])),
            allGroupsProvider.overrideWithValue(const AsyncValue.data([])),
            customFieldsProvider.overrideWithValue(const AsyncValue.data([])),
            customFieldsRepositoryProvider.overrideWithValue(
              customFieldsRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        final subscription = container.listen(
          tagUsageProvider(AppLocalizationsEn()),
          (_, _) {},
          fireImmediately: true,
        );

        await Future<void>.delayed(Duration.zero);
        subscription.close();
        await Future<void>.delayed(Duration.zero);

        customFieldsRepository.completeValues(const []);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(
          debugMessages,
          isNot(contains(contains('Cannot use the Ref of FutureProvider'))),
        );
      },
    );
  });
}

MediaAttachment _libraryAttachment() => MediaAttachment(
  id: 'att-flag',
  messageId: '',
  tag: 'flag',
  mediaId: 'media-flag',
  mediaType: 'image',
  encryptionKeyB64: base64Encode(List<int>.filled(32, 0)),
  contentHash: 'chash',
  plaintextHash: 'phash',
  mimeType: 'image/png',
  sizeBytes: 1,
  width: 1,
  height: 1,
  durationMs: 0,
  blurhash: '',
  waveformB64: '',
  thumbnailMediaId: '',
  sourceUrl: '',
  previewUrl: '',
);

class _BlockingCustomFieldsRepository implements CustomFieldsRepository {
  final _valuesCompleter = Completer<List<CustomFieldValue>>();

  void completeValues(List<CustomFieldValue> values) {
    _valuesCompleter.complete(values);
  }

  @override
  Future<List<CustomFieldValue>> getAllValues() => _valuesCompleter.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
