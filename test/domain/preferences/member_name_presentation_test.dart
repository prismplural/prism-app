import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/member_name_presentation.dart';

void main() {
  test('parses every stored value and rejects unknown values', () {
    for (final presentation in MemberNamePresentation.values) {
      expect(
        MemberNamePresentation.tryParse(presentation.storageValue),
        presentation,
      );
    }

    expect(MemberNamePresentation.tryParse('unknown'), isNull);
  });

  test('maps legacy member name display settings', () {
    expect(
      MemberNamePresentation.fromLegacy(MemberNameDisplay.display),
      MemberNamePresentation.fullName,
    );
    expect(
      MemberNamePresentation.fromLegacy(MemberNameDisplay.legacyName),
      MemberNamePresentation.nameWithFullName,
    );
  });

  test('derives primary name mode and alternate visibility', () {
    expect(MemberNamePresentation.fullName.primary, MemberNamePrimary.fullName);
    expect(MemberNamePresentation.fullName.preferDisplayName, isTrue);
    expect(MemberNamePresentation.fullName.showAlternateName, isFalse);

    expect(
      MemberNamePresentation.fullNameWithName.primary,
      MemberNamePrimary.fullName,
    );
    expect(MemberNamePresentation.fullNameWithName.preferDisplayName, isTrue);
    expect(MemberNamePresentation.fullNameWithName.showAlternateName, isTrue);

    expect(
      MemberNamePresentation.nameWithFullName.primary,
      MemberNamePrimary.canonicalName,
    );
    expect(MemberNamePresentation.nameWithFullName.preferDisplayName, isFalse);
    expect(MemberNamePresentation.nameWithFullName.showAlternateName, isTrue);

    expect(
      MemberNamePresentation.canonicalName.primary,
      MemberNamePrimary.canonicalName,
    );
    expect(MemberNamePresentation.canonicalName.preferDisplayName, isFalse);
    expect(MemberNamePresentation.canonicalName.showAlternateName, isFalse);
  });

  test('preserves alternate visibility when changing primary mode', () {
    expect(
      MemberNamePresentation.fullName.withPrimary(
        MemberNamePrimary.canonicalName,
      ),
      MemberNamePresentation.canonicalName,
    );
    expect(
      MemberNamePresentation.fullNameWithName.withPrimary(
        MemberNamePrimary.canonicalName,
      ),
      MemberNamePresentation.nameWithFullName,
    );
    expect(
      MemberNamePresentation.nameWithFullName.withPrimary(
        MemberNamePrimary.fullName,
      ),
      MemberNamePresentation.fullNameWithName,
    );
    expect(
      MemberNamePresentation.canonicalName.withPrimary(
        MemberNamePrimary.fullName,
      ),
      MemberNamePresentation.fullName,
    );
  });

  test('toggles alternate name visibility without changing primary mode', () {
    expect(
      MemberNamePresentation.fullName.withShowAlternateName(true),
      MemberNamePresentation.fullNameWithName,
    );
    expect(
      MemberNamePresentation.fullNameWithName.withShowAlternateName(false),
      MemberNamePresentation.fullName,
    );
    expect(
      MemberNamePresentation.canonicalName.withShowAlternateName(true),
      MemberNamePresentation.nameWithFullName,
    );
    expect(
      MemberNamePresentation.nameWithFullName.withShowAlternateName(false),
      MemberNamePresentation.canonicalName,
    );
  });

  test('alternateNameFor returns the non-primary name only when useful', () {
    final member = Member(
      id: 'm1',
      name: 'Aster',
      displayName: 'Beacon',
      createdAt: DateTime.utc(2026),
    );

    expect(
      alternateNameFor(member, MemberNamePresentation.fullNameWithName),
      'Aster',
    );
    expect(
      alternateNameFor(member, MemberNamePresentation.nameWithFullName),
      'Beacon',
    );
    expect(alternateNameFor(member, MemberNamePresentation.fullName), isNull);
    expect(
      alternateNameFor(member, MemberNamePresentation.canonicalName),
      isNull,
    );

    final sameName = member.copyWith(displayName: 'Aster');
    expect(
      alternateNameFor(sameName, MemberNamePresentation.nameWithFullName),
      isNull,
    );

    final blankDisplayName = member.copyWith(displayName: '   ');
    expect(
      alternateNameFor(
        blankDisplayName,
        MemberNamePresentation.nameWithFullName,
      ),
      isNull,
    );
  });
}
