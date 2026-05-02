import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/utils/member_profile_header_resolver.dart';

void main() {
  group('resolveMemberProfileHeader', () {
    test('uses Prism bytes when Prism is selected', () {
      final prismBytes = Uint8List.fromList([1, 2, 3]);
      final pkBytes = Uint8List.fromList([4, 5, 6]);

      final resolution = resolveMemberProfileHeader(
        _member(pkBannerUrl: 'https://cdn.example/banner.webp'),
        sourceOverride: MemberProfileHeaderSource.prism,
        prismImageDataOverride: prismBytes,
        pluralKitImageDataOverride: pkBytes,
      );

      expect(resolution.source, MemberProfileHeaderSource.prism);
      expect(resolution.activeImageData, same(prismBytes));
      expect(resolution.pluralKitEligible, isTrue);
    });

    test('uses PluralKit bytes when selected and eligible', () {
      final pkBytes = Uint8List.fromList([4, 5, 6]);

      final resolution = resolveMemberProfileHeader(
        _member(pluralkitId: 'abcde'),
        sourceOverride: MemberProfileHeaderSource.pluralKit,
        pluralKitImageDataOverride: pkBytes,
      );

      expect(resolution.source, MemberProfileHeaderSource.pluralKit);
      expect(resolution.activeImageData, same(pkBytes));
    });

    test('falls back to Prism when PluralKit is selected but ineligible', () {
      final prismBytes = Uint8List.fromList([1, 2, 3]);

      final resolution = resolveMemberProfileHeader(
        _member(),
        sourceOverride: MemberProfileHeaderSource.pluralKit,
        prismImageDataOverride: prismBytes,
      );

      expect(resolution.source, MemberProfileHeaderSource.prism);
      expect(resolution.activeImageData, same(prismBytes));
      expect(resolution.pluralKitEligible, isFalse);
    });

    test(
      'treats linked PluralKit members as eligible without cached bytes',
      () {
        expect(
          memberHasEligiblePluralKitHeader(_member(pluralkitUuid: 'uuid')),
          isTrue,
        );
        expect(
          memberHasEligiblePluralKitHeader(
            _member(pkBannerUrl: 'https://cdn.example/banner.webp'),
          ),
          isTrue,
        );
      },
    );

    test('ignores empty byte lists for active image resolution', () {
      final resolution = resolveMemberProfileHeader(
        _member(),
        sourceOverride: MemberProfileHeaderSource.prism,
        prismImageDataOverride: Uint8List(0),
      );

      expect(resolution.activeImageData, isNull);
      expect(resolution.hasImage, isFalse);
    });

    test(
      'visibility override suppresses active image without losing source',
      () {
        final resolution = resolveMemberProfileHeader(
          _member(),
          sourceOverride: MemberProfileHeaderSource.prism,
          visibleOverride: false,
          prismImageDataOverride: Uint8List.fromList([1, 2, 3]),
        );

        expect(resolution.visible, isFalse);
        expect(resolution.source, MemberProfileHeaderSource.prism);
        expect(resolution.activeImageData, isNull);
        expect(resolution.hasImage, isFalse);
      },
    );
  });
}

Member _member({
  String? pluralkitUuid,
  String? pluralkitId,
  String? pkBannerUrl,
}) {
  return Member(
    id: 'member-1',
    name: 'Aster',
    pluralkitUuid: pluralkitUuid,
    pluralkitId: pluralkitId,
    pkBannerUrl: pkBannerUrl,
    createdAt: DateTime.utc(2024),
  );
}
