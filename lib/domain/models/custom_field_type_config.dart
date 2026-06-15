import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:prism_plurality/domain/models/choice_option.dart';

part 'custom_field_type_config.freezed.dart';
part 'custom_field_type_config.g.dart';

enum CustomFieldHeaderIconKind { emoji, phosphor, unknown }

/// User-selected icon rendered in custom field headers.
///
/// Stored inside `type_config_json` so custom field header icons do not require
/// a database migration. Unknown future shapes are preserved verbatim so a
/// current build does not wipe a newer peer's icon payload.
class CustomFieldHeaderIcon {
  static const _deepEquality = DeepCollectionEquality();

  const CustomFieldHeaderIcon.emoji(String emoji)
    : kind = CustomFieldHeaderIconKind.emoji,
      value = emoji,
      raw = null;

  const CustomFieldHeaderIcon.phosphor(String name)
    : kind = CustomFieldHeaderIconKind.phosphor,
      value = name,
      raw = null;

  const CustomFieldHeaderIcon._unknown(this.raw)
    : kind = CustomFieldHeaderIconKind.unknown,
      value = null;

  factory CustomFieldHeaderIcon.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type == 'emoji') {
      final emoji = json['emoji'];
      if (emoji is String) return CustomFieldHeaderIcon.emoji(emoji);
    }
    if (type == 'phosphor') {
      final name = json['name'];
      if (name is String) return CustomFieldHeaderIcon.phosphor(name);
    }
    return CustomFieldHeaderIcon._unknown(Map<String, dynamic>.from(json));
  }

  final CustomFieldHeaderIconKind kind;
  final String? value;
  final Map<String, dynamic>? raw;

  String? get emoji => kind == CustomFieldHeaderIconKind.emoji ? value : null;

  String? get phosphorName =>
      kind == CustomFieldHeaderIconKind.phosphor ? value : null;

  Map<String, dynamic> toJson() {
    return switch (kind) {
      CustomFieldHeaderIconKind.emoji => {'type': 'emoji', 'emoji': value},
      CustomFieldHeaderIconKind.phosphor => {'type': 'phosphor', 'name': value},
      CustomFieldHeaderIconKind.unknown => <String, dynamic>{...?raw},
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CustomFieldHeaderIcon) return false;
    return kind == other.kind &&
        value == other.value &&
        _deepEquality.equals(raw, other.raw);
  }

  @override
  int get hashCode => Object.hash(kind, value, _deepEquality.hash(raw));

  @override
  String toString() => 'CustomFieldHeaderIcon(${toJson()})';
}

class CustomFieldHeaderIconConverter
    implements JsonConverter<CustomFieldHeaderIcon?, Object?> {
  const CustomFieldHeaderIconConverter();

  @override
  CustomFieldHeaderIcon? fromJson(Object? json) {
    if (json == null) return null;
    if (json is! Map) return null;
    return CustomFieldHeaderIcon.fromJson(Map<String, dynamic>.from(json));
  }

  @override
  Object? toJson(CustomFieldHeaderIcon? object) => object?.toJson();
}

enum SliderMode { labeled, numeric }

/// How a custom field's value renders on profile screens.
///
/// `compact` — label and value on the same row (label-left, value column right).
/// `stacked` — label on its own row above the value, full width below.
///
/// Null on a config = "use the type-aware default" (see
/// [effectiveDisplayLayout]).
enum DisplayLayout { compact, stacked }

/// Per-field overrides win over the type-aware default. Sliders always stack;
/// everything else defaults to compact.
DisplayLayout effectiveDisplayLayout({
  String? fieldTypeId,
  CustomFieldTypeConfig? typeConfig,
}) {
  if (typeConfig is ChoiceConfig && typeConfig.displayLayout != null) {
    return typeConfig.displayLayout!;
  }
  if (typeConfig is ScaleConfig && typeConfig.displayLayout != null) {
    return typeConfig.displayLayout!;
  }
  if (typeConfig is MemberConfig && typeConfig.displayLayout != null) {
    return typeConfig.displayLayout!;
  }
  if (fieldTypeId == 'slider') return DisplayLayout.stacked;
  return DisplayLayout.compact;
}

/// Type-specific config for all custom field types.
///
/// Legacy types (text, color, date, longText) previously had no variant — their
/// `typeConfigJson` column was NULL in storage. They now have minimal variants
/// holding just `hideTitleOnProfile` (+ `extra` for forward-compat).
///
/// Serialization caveat: plain freezed JSON drops unknown top-level keys.
/// Use [CustomFieldTypeConfigCodec] (see below) — NOT [_$CustomFieldTypeConfigFromJson]
/// directly — so forward-compat unknown keys are captured into `extra` and re-emitted.
@freezed
sealed class CustomFieldTypeConfig with _$CustomFieldTypeConfig {
  const factory CustomFieldTypeConfig.choice({
    @Default(<ChoiceOption>[]) List<ChoiceOption> options,
    @Default(false) bool allowsMultiple,
    @Default(false) bool allowsOther,
    DisplayLayout? displayLayout,
    @CustomFieldHeaderIconConverter() CustomFieldHeaderIcon? headerIcon,
    @Default(false) bool hideTitleOnProfile,
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = ChoiceConfig;

  const factory CustomFieldTypeConfig.group({
    String? icon,
    @CustomFieldHeaderIconConverter() CustomFieldHeaderIcon? headerIcon,
    @Default(false) bool hideTitleOnProfile,
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = GroupConfig;

  const factory CustomFieldTypeConfig.scale({
    @Default('⭐') String emoji,
    @Default(5) int steps,
    List<String>? stepLabels,
    DisplayLayout? displayLayout,
    @CustomFieldHeaderIconConverter() CustomFieldHeaderIcon? headerIcon,
    @Default(false) bool hideTitleOnProfile,
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = ScaleConfig;

  const factory CustomFieldTypeConfig.slider({
    required SliderMode mode,
    String? leftLabel,
    String? rightLabel,
    String? centerLabel,
    String? gradientPresetId,
    String? leftColorHex,
    String? rightColorHex,
    String? centerColorHex,
    List<String>? gradientColorsHex,
    @Default(false) bool snapToPositions,
    double? min,
    double? max,
    double? step,
    String? unit,
    @Default(false) bool showTicks,
    @CustomFieldHeaderIconConverter() CustomFieldHeaderIcon? headerIcon,
    @Default(false) bool hideTitleOnProfile,
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = SliderConfig;

  const factory CustomFieldTypeConfig.member({
    DisplayLayout? displayLayout,
    @CustomFieldHeaderIconConverter() CustomFieldHeaderIcon? headerIcon,
    @Default(false) bool hideTitleOnProfile,
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = MemberConfig;

  /// Minimal variant for text fields. Previously typeConfigJson was always NULL;
  /// now written when hideTitleOnProfile is set (or to preserve forward-compat extras).
  const factory CustomFieldTypeConfig.text({
    @CustomFieldHeaderIconConverter() CustomFieldHeaderIcon? headerIcon,
    @Default(false) bool hideTitleOnProfile,
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = TextConfig;

  /// Minimal variant for color fields. See [TextConfig] note above.
  const factory CustomFieldTypeConfig.color({
    @CustomFieldHeaderIconConverter() CustomFieldHeaderIcon? headerIcon,
    @Default(false) bool hideTitleOnProfile,
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = ColorConfig;

  /// Minimal variant for date fields. See [TextConfig] note above.
  /// Note: date precision is stored in its own top-level column, unrelated to this.
  const factory CustomFieldTypeConfig.date({
    @CustomFieldHeaderIconConverter() CustomFieldHeaderIcon? headerIcon,
    @Default(false) bool hideTitleOnProfile,
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = DateConfig;

  /// Minimal variant for long_text fields. See [TextConfig] note above.
  const factory CustomFieldTypeConfig.longText({
    @CustomFieldHeaderIconConverter() CustomFieldHeaderIcon? headerIcon,
    @Default(false) bool hideTitleOnProfile,
    @Default(<String, dynamic>{})
    @JsonKey(includeFromJson: false, includeToJson: false)
    Map<String, dynamic> extra,
  }) = LongTextConfig;

  factory CustomFieldTypeConfig.fromJson(Map<String, dynamic> json) =>
      _$CustomFieldTypeConfigFromJson(json);
}

/// Wrapper around [CustomFieldTypeConfig]'s generated JSON that preserves
/// unknown top-level keys for forward-compat (whole-config LWW).
///
/// IMPORTANT: Always use this class — NOT freezed's generated fromJson/toJson
/// directly — so v28 readers never silently drop config fields added by future
/// versions. This is the single sanctioned entry point for JSON ↔ sealed config.
class CustomFieldTypeConfigCodec {
  CustomFieldTypeConfigCodec._();

  /// Decode a JSON object into the sealed variant. Any top-level keys not
  /// recognized by the matched variant are captured into the variant's `extra` map.
  ///
  /// For [ChoiceConfig], each nested option is rebuilt via [ChoiceOptionCodec]
  /// so unknown option-level keys land in the option's own `extra` map (the
  /// freezed-generated decoder would otherwise drop them).
  static CustomFieldTypeConfig fromJson(Map<String, dynamic> json) {
    final config = CustomFieldTypeConfig.fromJson(json);
    final hydrated = switch (config) {
      final ChoiceConfig c => c.copyWith(
        options: ((json['options'] as List<dynamic>?) ?? const <dynamic>[])
            .map((e) => ChoiceOptionCodec.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      _ => config,
    };
    final known = _knownKeysFor(hydrated);
    final extra = <String, dynamic>{};
    for (final entry in json.entries) {
      if (entry.key == 'runtimeType') continue;
      if (!known.contains(entry.key)) {
        extra[entry.key] = entry.value;
      }
    }
    if (extra.isEmpty) return hydrated;
    return switch (hydrated) {
      final ChoiceConfig c => c.copyWith(extra: extra),
      final GroupConfig c => c.copyWith(extra: extra),
      final ScaleConfig c => c.copyWith(extra: extra),
      final SliderConfig c => c.copyWith(extra: extra),
      final MemberConfig c => c.copyWith(extra: extra),
      final TextConfig c => c.copyWith(extra: extra),
      final ColorConfig c => c.copyWith(extra: extra),
      final DateConfig c => c.copyWith(extra: extra),
      final LongTextConfig c => c.copyWith(extra: extra),
    };
  }

  /// Encode the sealed variant to JSON. The variant's `extra` map is merged
  /// back at the top level so unknown forward-compat keys re-emit intact.
  ///
  /// Extras keys are emitted in alphabetical order so re-encoding is stable
  /// regardless of the on-disk key order written by the peer. Without this,
  /// any v29-peer write whose keys do not match the codec's emit order would
  /// produce a phantom `type_config_json` op on the first v28 read→write —
  /// the diff would see "changed bytes" even though the logical content is
  /// identical.
  ///
  /// Note: nested [ChoiceOption] objects are explicitly serialized via
  /// [ChoiceOptionCodec] so the result is a plain `Map<String, dynamic>`
  /// that can be safely passed back into [fromJson] without a
  /// jsonEncode/jsonDecode round-trip, and so option-level extras are also
  /// emitted in stable order.
  static Map<String, dynamic> toJson(CustomFieldTypeConfig config) {
    final base = _toJsonDeep(config);
    final extra = switch (config) {
      final ChoiceConfig c => c.extra,
      final GroupConfig c => c.extra,
      final ScaleConfig c => c.extra,
      final SliderConfig c => c.extra,
      final MemberConfig c => c.extra,
      final TextConfig c => c.extra,
      final ColorConfig c => c.extra,
      final DateConfig c => c.extra,
      final LongTextConfig c => c.extra,
    };
    if (extra.isEmpty) return base;
    final sortedExtraKeys = extra.keys.toList()..sort();
    final out = <String, dynamic>{...base};
    for (final key in sortedExtraKeys) {
      out[key] = extra[key];
    }
    return out;
  }

  /// Produces a fully serialized map (all nested objects converted to maps).
  ///
  /// Nested [ChoiceOption]s are serialized through [ChoiceOptionCodec] so
  /// unknown option-level keys (e.g. a v29 peer adding `iconKey`) survive a
  /// v28 read→write — symmetric with how the top-level codec preserves
  /// unknown variant-level keys.
  static Map<String, dynamic> _toJsonDeep(CustomFieldTypeConfig config) {
    return switch (config) {
      final ChoiceConfig c => {
        ...c.toJson(),
        'options': c.options.map(ChoiceOptionCodec.toJson).toList(),
      },
      // All other variants have no nested freezed objects.
      GroupConfig _ => config.toJson(),
      ScaleConfig _ => config.toJson(),
      SliderConfig _ => config.toJson(),
      MemberConfig _ => config.toJson(),
      TextConfig _ => config.toJson(),
      ColorConfig _ => config.toJson(),
      DateConfig _ => config.toJson(),
      LongTextConfig _ => config.toJson(),
    };
  }

  /// Known top-level keys for the matched variant (everything else goes in extra).
  /// Update this when adding new fields to a variant.
  ///
  // INVARIANT: every freezed field on a variant MUST appear in its set here.
  // Missing a key causes round-trip to duplicate it into both the typed field
  // and `extra`.
  static Set<String> _knownKeysFor(CustomFieldTypeConfig config) {
    return switch (config) {
      ChoiceConfig _ => const {
        'runtimeType',
        'options',
        'allowsMultiple',
        'allowsOther',
        'displayLayout',
        'headerIcon',
        'hideTitleOnProfile',
      },
      GroupConfig _ => const {
        'runtimeType',
        'icon',
        'headerIcon',
        'hideTitleOnProfile',
      },
      ScaleConfig _ => const {
        'runtimeType',
        'emoji',
        'steps',
        'stepLabels',
        'displayLayout',
        'headerIcon',
        'hideTitleOnProfile',
      },
      SliderConfig _ => const {
        'runtimeType',
        'mode',
        'leftLabel',
        'rightLabel',
        'centerLabel',
        'gradientPresetId',
        'leftColorHex',
        'rightColorHex',
        'centerColorHex',
        'gradientColorsHex',
        'snapToPositions',
        'min',
        'max',
        'step',
        'unit',
        'showTicks',
        'headerIcon',
        'hideTitleOnProfile',
      },
      MemberConfig _ => const {
        'runtimeType',
        'displayLayout',
        'headerIcon',
        'hideTitleOnProfile',
      },
      TextConfig _ => const {'runtimeType', 'headerIcon', 'hideTitleOnProfile'},
      ColorConfig _ => const {
        'runtimeType',
        'headerIcon',
        'hideTitleOnProfile',
      },
      DateConfig _ => const {'runtimeType', 'headerIcon', 'hideTitleOnProfile'},
      LongTextConfig _ => const {
        'runtimeType',
        'headerIcon',
        'hideTitleOnProfile',
      },
    };
  }
}

/// Read [hideTitleOnProfile] from any variant; returns false for null
/// (no typeConfig at all). Mirror of [effectiveDisplayLayout].
bool effectiveHideTitleOnProfile(CustomFieldTypeConfig? config) =>
    switch (config) {
      null => false,
      final ChoiceConfig c => c.hideTitleOnProfile,
      final GroupConfig c => c.hideTitleOnProfile,
      final ScaleConfig c => c.hideTitleOnProfile,
      final SliderConfig c => c.hideTitleOnProfile,
      final MemberConfig c => c.hideTitleOnProfile,
      final TextConfig c => c.hideTitleOnProfile,
      final ColorConfig c => c.hideTitleOnProfile,
      final DateConfig c => c.hideTitleOnProfile,
      final LongTextConfig c => c.hideTitleOnProfile,
    };

CustomFieldHeaderIcon? effectiveHeaderIcon(CustomFieldTypeConfig? config) =>
    switch (config) {
      null => null,
      final ChoiceConfig c => c.headerIcon,
      final GroupConfig c => c.headerIcon,
      final ScaleConfig c => c.headerIcon,
      final SliderConfig c => c.headerIcon,
      final MemberConfig c => c.headerIcon,
      final TextConfig c => c.headerIcon,
      final ColorConfig c => c.headerIcon,
      final DateConfig c => c.headerIcon,
      final LongTextConfig c => c.headerIcon,
    };
