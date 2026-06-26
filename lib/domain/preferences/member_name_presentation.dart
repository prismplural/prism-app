import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';

enum MemberNamePrimary { fullName, canonicalName }

enum MemberNamePresentation {
  fullName('full_name'),
  fullNameWithName('full_name_with_name'),
  nameWithFullName('name_with_full_name'),
  canonicalName('name');

  const MemberNamePresentation(this.storageValue);

  final String storageValue;

  static MemberNamePresentation? tryParse(String value) {
    for (final presentation in values) {
      if (presentation.storageValue == value) return presentation;
    }
    return null;
  }

  static MemberNamePresentation fromLegacy(MemberNameDisplay value) {
    return switch (value) {
      MemberNameDisplay.display => MemberNamePresentation.fullName,
      MemberNameDisplay.legacyName => MemberNamePresentation.nameWithFullName,
    };
  }

  MemberNamePrimary get primary => switch (this) {
    MemberNamePresentation.fullName ||
    MemberNamePresentation.fullNameWithName => MemberNamePrimary.fullName,
    MemberNamePresentation.nameWithFullName ||
    MemberNamePresentation.canonicalName => MemberNamePrimary.canonicalName,
  };

  bool get preferDisplayName => primary == MemberNamePrimary.fullName;

  bool get showAlternateName => switch (this) {
    MemberNamePresentation.fullNameWithName ||
    MemberNamePresentation.nameWithFullName => true,
    MemberNamePresentation.fullName ||
    MemberNamePresentation.canonicalName => false,
  };

  MemberNamePresentation withPrimary(MemberNamePrimary value) {
    final showAlternate = showAlternateName;
    return switch (value) {
      MemberNamePrimary.fullName =>
        showAlternate
            ? MemberNamePresentation.fullNameWithName
            : MemberNamePresentation.fullName,
      MemberNamePrimary.canonicalName =>
        showAlternate
            ? MemberNamePresentation.nameWithFullName
            : MemberNamePresentation.canonicalName,
    };
  }

  MemberNamePresentation withShowAlternateName(bool value) {
    return switch ((primary, value)) {
      (MemberNamePrimary.fullName, true) =>
        MemberNamePresentation.fullNameWithName,
      (MemberNamePrimary.fullName, false) => MemberNamePresentation.fullName,
      (MemberNamePrimary.canonicalName, true) =>
        MemberNamePresentation.nameWithFullName,
      (MemberNamePrimary.canonicalName, false) =>
        MemberNamePresentation.canonicalName,
    };
  }
}

String primaryNameFor(Member member, MemberNamePresentation presentation) {
  return member.effectiveName(
    preferDisplayName: presentation.preferDisplayName,
  );
}

String? alternateNameFor(Member member, MemberNamePresentation presentation) {
  if (!presentation.showAlternateName) return null;
  final primary = primaryNameFor(member, presentation);
  final alternate = switch (presentation.primary) {
    MemberNamePrimary.fullName => member.name.trim(),
    MemberNamePrimary.canonicalName => member.displayName?.trim(),
  };
  if (alternate == null || alternate.isEmpty || alternate == primary) {
    return null;
  }
  return alternate;
}
