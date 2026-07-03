import 'package:prism_plurality/domain/preferences/preference_codec.dart';

const systemTermMaxLength = 40;

enum SystemTermPreset { collective, community, network, constellation }

final class SystemTerms {
  const SystemTerms({this.preset, this.singular, this.plural});

  const SystemTerms.preset(SystemTermPreset preset) : this(preset: preset);

  const SystemTerms.custom({required String singular, required String plural})
    : this(singular: singular, plural: plural);

  static const unset = SystemTerms();

  final SystemTermPreset? preset;
  final String? singular;
  final String? plural;

  bool get isUnset =>
      preset == null &&
      (singular == null || singular!.trim().isEmpty) &&
      (plural == null || plural!.trim().isEmpty);

  SystemTerms normalized() {
    if (preset != null) return SystemTerms.preset(preset!);

    final normalizedSingular = singular?.trim();
    final normalizedPlural = plural?.trim();
    if ((normalizedSingular == null || normalizedSingular.isEmpty) &&
        (normalizedPlural == null || normalizedPlural.isEmpty)) {
      return unset;
    }
    return SystemTerms(singular: normalizedSingular, plural: normalizedPlural);
  }

  Map<String, Object?> toJson() => {
    if (preset != null) 'preset': preset!.name,
    if (singular != null) 'singular': singular,
    if (plural != null) 'plural': plural,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemTerms &&
          other.preset == preset &&
          other.singular == singular &&
          other.plural == plural;

  @override
  int get hashCode => Object.hash(preset, singular, plural);

  @override
  String toString() =>
      'SystemTerms(preset: $preset, singular: $singular, plural: $plural)';
}

final class SystemTermsPreferenceCodec extends PreferenceCodec<SystemTerms> {
  const SystemTermsPreferenceCodec();

  @override
  String get valueType => 'json';

  @override
  Object? encode(SystemTerms value) => value.normalized().toJson();

  @override
  SystemTerms decode(Object? value) {
    if (value is! Map) return SystemTerms.unset;
    final presetName = value['preset'];
    if (presetName is String) {
      final preset = _presetByName(presetName);
      if (preset != null) return SystemTerms.preset(preset);
      return SystemTerms.unset;
    }

    final singular = value['singular'];
    final plural = value['plural'];
    if (singular is! String || plural is! String) return SystemTerms.unset;

    final terms = SystemTerms.custom(
      singular: singular,
      plural: plural,
    ).normalized();
    return isValid(terms) ? terms : SystemTerms.unset;
  }

  @override
  bool isValid(SystemTerms value) {
    if (value.preset != null) return true;
    if (value.isUnset) return false;
    final singular = value.singular?.trim();
    final plural = value.plural?.trim();
    if (singular == null || plural == null) return false;
    if (singular.isEmpty || plural.isEmpty) return false;
    if (singular.length > systemTermMaxLength) return false;
    if (plural.length > systemTermMaxLength) return false;
    return true;
  }

  static SystemTermPreset? _presetByName(String name) {
    for (final preset in SystemTermPreset.values) {
      if (preset.name == name) return preset;
    }
    return null;
  }
}
