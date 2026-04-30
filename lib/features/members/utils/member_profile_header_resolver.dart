import 'dart:typed_data';

import 'package:prism_plurality/domain/models/member.dart';

class MemberProfileHeaderResolution {
  const MemberProfileHeaderResolution({
    required this.source,
    required this.layout,
    required this.activeImageData,
    required this.pluralKitEligible,
    required this.pluralKitImageData,
    required this.prismImageData,
  });

  final MemberProfileHeaderSource source;
  final MemberProfileHeaderLayout layout;
  final Uint8List? activeImageData;
  final bool pluralKitEligible;
  final Uint8List? pluralKitImageData;
  final Uint8List? prismImageData;

  bool get hasImage => activeImageData != null && activeImageData!.isNotEmpty;
}

MemberProfileHeaderResolution resolveMemberProfileHeader(
  Member member, {
  MemberProfileHeaderSource? sourceOverride,
  MemberProfileHeaderLayout? layoutOverride,
  Uint8List? prismImageDataOverride,
  Uint8List? pluralKitImageDataOverride,
}) {
  final prismImageData =
      prismImageDataOverride ??
      _futureBytes(member, _FutureMemberField.profileHeaderImageData);
  final pluralKitImageData =
      pluralKitImageDataOverride ??
      _futureBytes(member, _FutureMemberField.pkBannerImageData);
  final pluralKitEligible = memberHasEligiblePluralKitHeader(
    member,
    pluralKitImageDataOverride: pluralKitImageData,
  );
  final requestedSource =
      sourceOverride ??
      _futureSource(member, _FutureMemberField.profileHeaderSource) ??
      _defaultSource(member, pluralKitEligible);
  final source =
      requestedSource == MemberProfileHeaderSource.pluralKit &&
          pluralKitEligible
      ? MemberProfileHeaderSource.pluralKit
      : MemberProfileHeaderSource.prism;
  final layout =
      layoutOverride ??
      _futureLayout(member, _FutureMemberField.profileHeaderLayout) ??
      MemberProfileHeaderLayout.compactBackground;
  final activeImageData = switch (source) {
    MemberProfileHeaderSource.pluralKit => _nonEmptyBytes(pluralKitImageData),
    MemberProfileHeaderSource.prism => _nonEmptyBytes(prismImageData),
  };

  return MemberProfileHeaderResolution(
    source: source,
    layout: layout,
    activeImageData: activeImageData,
    pluralKitEligible: pluralKitEligible,
    pluralKitImageData: _nonEmptyBytes(pluralKitImageData),
    prismImageData: _nonEmptyBytes(prismImageData),
  );
}

bool memberHasEligiblePluralKitHeader(
  Member member, {
  Uint8List? pluralKitImageDataOverride,
}) {
  final cachedBytes =
      pluralKitImageDataOverride ??
      _futureBytes(member, _FutureMemberField.pkBannerImageData);
  return _hasText(member.pluralkitUuid) ||
      _hasText(member.pluralkitId) ||
      _hasText(member.pkBannerUrl) ||
      _hasText(_futureString(member, _FutureMemberField.pkBannerCachedUrl)) ||
      _nonEmptyBytes(cachedBytes) != null;
}

Uint8List? _nonEmptyBytes(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  return bytes;
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

MemberProfileHeaderSource _defaultSource(
  Member member,
  bool pluralKitEligible,
) {
  if (pluralKitEligible && _hasText(member.pkBannerUrl)) {
    return MemberProfileHeaderSource.pluralKit;
  }
  return MemberProfileHeaderSource.prism;
}

enum _FutureMemberField {
  profileHeaderSource,
  profileHeaderLayout,
  profileHeaderImageData,
  pkBannerImageData,
  pkBannerCachedUrl,
}

Object? _futureValue(Member member, _FutureMemberField field) {
  final dynamic futureMember = member;
  try {
    return switch (field) {
      _FutureMemberField.profileHeaderSource =>
        futureMember.profileHeaderSource,
      _FutureMemberField.profileHeaderLayout =>
        futureMember.profileHeaderLayout,
      _FutureMemberField.profileHeaderImageData =>
        futureMember.profileHeaderImageData,
      _FutureMemberField.pkBannerImageData => futureMember.pkBannerImageData,
      _FutureMemberField.pkBannerCachedUrl => futureMember.pkBannerCachedUrl,
    };
  } on NoSuchMethodError {
    return null;
  }
}

Uint8List? _futureBytes(Member member, _FutureMemberField field) {
  final value = _futureValue(member, field);
  return value is Uint8List ? value : null;
}

String? _futureString(Member member, _FutureMemberField field) {
  final value = _futureValue(member, field);
  return value is String ? value : null;
}

MemberProfileHeaderSource? _futureSource(
  Member member,
  _FutureMemberField field,
) {
  final value = _futureValue(member, field);
  if (value is MemberProfileHeaderSource) return value;
  final name = _enumName(value);
  return switch (name) {
    'pluralKit' => MemberProfileHeaderSource.pluralKit,
    'prism' => MemberProfileHeaderSource.prism,
    _ => null,
  };
}

MemberProfileHeaderLayout? _futureLayout(
  Member member,
  _FutureMemberField field,
) {
  final value = _futureValue(member, field);
  if (value is MemberProfileHeaderLayout) return value;
  final name = _enumName(value);
  return switch (name) {
    'compactBackground' => MemberProfileHeaderLayout.compactBackground,
    'classicOverlap' => MemberProfileHeaderLayout.classicOverlap,
    _ => null,
  };
}

String? _enumName(Object? value) {
  if (value == null) return null;
  try {
    final dynamic enumValue = value;
    final name = enumValue.name;
    if (name is String) return name;
  } on NoSuchMethodError {
    return null;
  }
  return null;
}
