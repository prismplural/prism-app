// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'habit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Habit {

 String get id; String get name; String? get description; String? get icon; String? get colorHex; bool get isActive; DateTime get createdAt; DateTime get modifiedAt; HabitFrequency get frequency; List<int>? get weeklyDays; int? get intervalDays; String? get reminderTime; bool get notificationsEnabled; String? get notificationMessage; String? get assignedMemberId; bool get onlyNotifyWhenFronting; bool get isPrivate; int get currentStreak; int get bestStreak; int get totalCompletions;
/// Create a copy of Habit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HabitCopyWith<Habit> get copyWith => _$HabitCopyWithImpl<Habit>(this as Habit, _$identity);

  /// Serializes this Habit to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Habit&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.icon, icon) || other.icon == icon)&&(identical(other.colorHex, colorHex) || other.colorHex == colorHex)&&(identical(other.isActive, isActive) || other.isActive == isActive)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.modifiedAt, modifiedAt) || other.modifiedAt == modifiedAt)&&(identical(other.frequency, frequency) || other.frequency == frequency)&&const DeepCollectionEquality().equals(other.weeklyDays, weeklyDays)&&(identical(other.intervalDays, intervalDays) || other.intervalDays == intervalDays)&&(identical(other.reminderTime, reminderTime) || other.reminderTime == reminderTime)&&(identical(other.notificationsEnabled, notificationsEnabled) || other.notificationsEnabled == notificationsEnabled)&&(identical(other.notificationMessage, notificationMessage) || other.notificationMessage == notificationMessage)&&(identical(other.assignedMemberId, assignedMemberId) || other.assignedMemberId == assignedMemberId)&&(identical(other.onlyNotifyWhenFronting, onlyNotifyWhenFronting) || other.onlyNotifyWhenFronting == onlyNotifyWhenFronting)&&(identical(other.isPrivate, isPrivate) || other.isPrivate == isPrivate)&&(identical(other.currentStreak, currentStreak) || other.currentStreak == currentStreak)&&(identical(other.bestStreak, bestStreak) || other.bestStreak == bestStreak)&&(identical(other.totalCompletions, totalCompletions) || other.totalCompletions == totalCompletions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,name,description,icon,colorHex,isActive,createdAt,modifiedAt,frequency,const DeepCollectionEquality().hash(weeklyDays),intervalDays,reminderTime,notificationsEnabled,notificationMessage,assignedMemberId,onlyNotifyWhenFronting,isPrivate,currentStreak,bestStreak,totalCompletions]);

@override
String toString() {
  return 'Habit(id: $id, name: $name, description: $description, icon: $icon, colorHex: $colorHex, isActive: $isActive, createdAt: $createdAt, modifiedAt: $modifiedAt, frequency: $frequency, weeklyDays: $weeklyDays, intervalDays: $intervalDays, reminderTime: $reminderTime, notificationsEnabled: $notificationsEnabled, notificationMessage: $notificationMessage, assignedMemberId: $assignedMemberId, onlyNotifyWhenFronting: $onlyNotifyWhenFronting, isPrivate: $isPrivate, currentStreak: $currentStreak, bestStreak: $bestStreak, totalCompletions: $totalCompletions)';
}


}

/// @nodoc
abstract mixin class $HabitCopyWith<$Res>  {
  factory $HabitCopyWith(Habit value, $Res Function(Habit) _then) = _$HabitCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? description, String? icon, String? colorHex, bool isActive, DateTime createdAt, DateTime modifiedAt, HabitFrequency frequency, List<int>? weeklyDays, int? intervalDays, String? reminderTime, bool notificationsEnabled, String? notificationMessage, String? assignedMemberId, bool onlyNotifyWhenFronting, bool isPrivate, int currentStreak, int bestStreak, int totalCompletions
});




}
/// @nodoc
class _$HabitCopyWithImpl<$Res>
    implements $HabitCopyWith<$Res> {
  _$HabitCopyWithImpl(this._self, this._then);

  final Habit _self;
  final $Res Function(Habit) _then;

/// Create a copy of Habit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? icon = freezed,Object? colorHex = freezed,Object? isActive = null,Object? createdAt = null,Object? modifiedAt = null,Object? frequency = null,Object? weeklyDays = freezed,Object? intervalDays = freezed,Object? reminderTime = freezed,Object? notificationsEnabled = null,Object? notificationMessage = freezed,Object? assignedMemberId = freezed,Object? onlyNotifyWhenFronting = null,Object? isPrivate = null,Object? currentStreak = null,Object? bestStreak = null,Object? totalCompletions = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,icon: freezed == icon ? _self.icon : icon // ignore: cast_nullable_to_non_nullable
as String?,colorHex: freezed == colorHex ? _self.colorHex : colorHex // ignore: cast_nullable_to_non_nullable
as String?,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,modifiedAt: null == modifiedAt ? _self.modifiedAt : modifiedAt // ignore: cast_nullable_to_non_nullable
as DateTime,frequency: null == frequency ? _self.frequency : frequency // ignore: cast_nullable_to_non_nullable
as HabitFrequency,weeklyDays: freezed == weeklyDays ? _self.weeklyDays : weeklyDays // ignore: cast_nullable_to_non_nullable
as List<int>?,intervalDays: freezed == intervalDays ? _self.intervalDays : intervalDays // ignore: cast_nullable_to_non_nullable
as int?,reminderTime: freezed == reminderTime ? _self.reminderTime : reminderTime // ignore: cast_nullable_to_non_nullable
as String?,notificationsEnabled: null == notificationsEnabled ? _self.notificationsEnabled : notificationsEnabled // ignore: cast_nullable_to_non_nullable
as bool,notificationMessage: freezed == notificationMessage ? _self.notificationMessage : notificationMessage // ignore: cast_nullable_to_non_nullable
as String?,assignedMemberId: freezed == assignedMemberId ? _self.assignedMemberId : assignedMemberId // ignore: cast_nullable_to_non_nullable
as String?,onlyNotifyWhenFronting: null == onlyNotifyWhenFronting ? _self.onlyNotifyWhenFronting : onlyNotifyWhenFronting // ignore: cast_nullable_to_non_nullable
as bool,isPrivate: null == isPrivate ? _self.isPrivate : isPrivate // ignore: cast_nullable_to_non_nullable
as bool,currentStreak: null == currentStreak ? _self.currentStreak : currentStreak // ignore: cast_nullable_to_non_nullable
as int,bestStreak: null == bestStreak ? _self.bestStreak : bestStreak // ignore: cast_nullable_to_non_nullable
as int,totalCompletions: null == totalCompletions ? _self.totalCompletions : totalCompletions // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [Habit].
extension HabitPatterns on Habit {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Habit value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Habit() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Habit value)  $default,){
final _that = this;
switch (_that) {
case _Habit():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Habit value)?  $default,){
final _that = this;
switch (_that) {
case _Habit() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  String? icon,  String? colorHex,  bool isActive,  DateTime createdAt,  DateTime modifiedAt,  HabitFrequency frequency,  List<int>? weeklyDays,  int? intervalDays,  String? reminderTime,  bool notificationsEnabled,  String? notificationMessage,  String? assignedMemberId,  bool onlyNotifyWhenFronting,  bool isPrivate,  int currentStreak,  int bestStreak,  int totalCompletions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Habit() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.icon,_that.colorHex,_that.isActive,_that.createdAt,_that.modifiedAt,_that.frequency,_that.weeklyDays,_that.intervalDays,_that.reminderTime,_that.notificationsEnabled,_that.notificationMessage,_that.assignedMemberId,_that.onlyNotifyWhenFronting,_that.isPrivate,_that.currentStreak,_that.bestStreak,_that.totalCompletions);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  String? icon,  String? colorHex,  bool isActive,  DateTime createdAt,  DateTime modifiedAt,  HabitFrequency frequency,  List<int>? weeklyDays,  int? intervalDays,  String? reminderTime,  bool notificationsEnabled,  String? notificationMessage,  String? assignedMemberId,  bool onlyNotifyWhenFronting,  bool isPrivate,  int currentStreak,  int bestStreak,  int totalCompletions)  $default,) {final _that = this;
switch (_that) {
case _Habit():
return $default(_that.id,_that.name,_that.description,_that.icon,_that.colorHex,_that.isActive,_that.createdAt,_that.modifiedAt,_that.frequency,_that.weeklyDays,_that.intervalDays,_that.reminderTime,_that.notificationsEnabled,_that.notificationMessage,_that.assignedMemberId,_that.onlyNotifyWhenFronting,_that.isPrivate,_that.currentStreak,_that.bestStreak,_that.totalCompletions);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? description,  String? icon,  String? colorHex,  bool isActive,  DateTime createdAt,  DateTime modifiedAt,  HabitFrequency frequency,  List<int>? weeklyDays,  int? intervalDays,  String? reminderTime,  bool notificationsEnabled,  String? notificationMessage,  String? assignedMemberId,  bool onlyNotifyWhenFronting,  bool isPrivate,  int currentStreak,  int bestStreak,  int totalCompletions)?  $default,) {final _that = this;
switch (_that) {
case _Habit() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.icon,_that.colorHex,_that.isActive,_that.createdAt,_that.modifiedAt,_that.frequency,_that.weeklyDays,_that.intervalDays,_that.reminderTime,_that.notificationsEnabled,_that.notificationMessage,_that.assignedMemberId,_that.onlyNotifyWhenFronting,_that.isPrivate,_that.currentStreak,_that.bestStreak,_that.totalCompletions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Habit extends Habit {
  const _Habit({required this.id, required this.name, this.description, this.icon, this.colorHex, this.isActive = true, required this.createdAt, required this.modifiedAt, this.frequency = HabitFrequency.daily, final  List<int>? weeklyDays, this.intervalDays, this.reminderTime, this.notificationsEnabled = false, this.notificationMessage, this.assignedMemberId, this.onlyNotifyWhenFronting = false, this.isPrivate = false, this.currentStreak = 0, this.bestStreak = 0, this.totalCompletions = 0}): _weeklyDays = weeklyDays,super._();
  factory _Habit.fromJson(Map<String, dynamic> json) => _$HabitFromJson(json);

@override final  String id;
@override final  String name;
@override final  String? description;
@override final  String? icon;
@override final  String? colorHex;
@override@JsonKey() final  bool isActive;
@override final  DateTime createdAt;
@override final  DateTime modifiedAt;
@override@JsonKey() final  HabitFrequency frequency;
 final  List<int>? _weeklyDays;
@override List<int>? get weeklyDays {
  final value = _weeklyDays;
  if (value == null) return null;
  if (_weeklyDays is EqualUnmodifiableListView) return _weeklyDays;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

@override final  int? intervalDays;
@override final  String? reminderTime;
@override@JsonKey() final  bool notificationsEnabled;
@override final  String? notificationMessage;
@override final  String? assignedMemberId;
@override@JsonKey() final  bool onlyNotifyWhenFronting;
@override@JsonKey() final  bool isPrivate;
@override@JsonKey() final  int currentStreak;
@override@JsonKey() final  int bestStreak;
@override@JsonKey() final  int totalCompletions;

/// Create a copy of Habit
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HabitCopyWith<_Habit> get copyWith => __$HabitCopyWithImpl<_Habit>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$HabitToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Habit&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.icon, icon) || other.icon == icon)&&(identical(other.colorHex, colorHex) || other.colorHex == colorHex)&&(identical(other.isActive, isActive) || other.isActive == isActive)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.modifiedAt, modifiedAt) || other.modifiedAt == modifiedAt)&&(identical(other.frequency, frequency) || other.frequency == frequency)&&const DeepCollectionEquality().equals(other._weeklyDays, _weeklyDays)&&(identical(other.intervalDays, intervalDays) || other.intervalDays == intervalDays)&&(identical(other.reminderTime, reminderTime) || other.reminderTime == reminderTime)&&(identical(other.notificationsEnabled, notificationsEnabled) || other.notificationsEnabled == notificationsEnabled)&&(identical(other.notificationMessage, notificationMessage) || other.notificationMessage == notificationMessage)&&(identical(other.assignedMemberId, assignedMemberId) || other.assignedMemberId == assignedMemberId)&&(identical(other.onlyNotifyWhenFronting, onlyNotifyWhenFronting) || other.onlyNotifyWhenFronting == onlyNotifyWhenFronting)&&(identical(other.isPrivate, isPrivate) || other.isPrivate == isPrivate)&&(identical(other.currentStreak, currentStreak) || other.currentStreak == currentStreak)&&(identical(other.bestStreak, bestStreak) || other.bestStreak == bestStreak)&&(identical(other.totalCompletions, totalCompletions) || other.totalCompletions == totalCompletions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,name,description,icon,colorHex,isActive,createdAt,modifiedAt,frequency,const DeepCollectionEquality().hash(_weeklyDays),intervalDays,reminderTime,notificationsEnabled,notificationMessage,assignedMemberId,onlyNotifyWhenFronting,isPrivate,currentStreak,bestStreak,totalCompletions]);

@override
String toString() {
  return 'Habit(id: $id, name: $name, description: $description, icon: $icon, colorHex: $colorHex, isActive: $isActive, createdAt: $createdAt, modifiedAt: $modifiedAt, frequency: $frequency, weeklyDays: $weeklyDays, intervalDays: $intervalDays, reminderTime: $reminderTime, notificationsEnabled: $notificationsEnabled, notificationMessage: $notificationMessage, assignedMemberId: $assignedMemberId, onlyNotifyWhenFronting: $onlyNotifyWhenFronting, isPrivate: $isPrivate, currentStreak: $currentStreak, bestStreak: $bestStreak, totalCompletions: $totalCompletions)';
}


}

/// @nodoc
abstract mixin class _$HabitCopyWith<$Res> implements $HabitCopyWith<$Res> {
  factory _$HabitCopyWith(_Habit value, $Res Function(_Habit) _then) = __$HabitCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? description, String? icon, String? colorHex, bool isActive, DateTime createdAt, DateTime modifiedAt, HabitFrequency frequency, List<int>? weeklyDays, int? intervalDays, String? reminderTime, bool notificationsEnabled, String? notificationMessage, String? assignedMemberId, bool onlyNotifyWhenFronting, bool isPrivate, int currentStreak, int bestStreak, int totalCompletions
});




}
/// @nodoc
class __$HabitCopyWithImpl<$Res>
    implements _$HabitCopyWith<$Res> {
  __$HabitCopyWithImpl(this._self, this._then);

  final _Habit _self;
  final $Res Function(_Habit) _then;

/// Create a copy of Habit
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? icon = freezed,Object? colorHex = freezed,Object? isActive = null,Object? createdAt = null,Object? modifiedAt = null,Object? frequency = null,Object? weeklyDays = freezed,Object? intervalDays = freezed,Object? reminderTime = freezed,Object? notificationsEnabled = null,Object? notificationMessage = freezed,Object? assignedMemberId = freezed,Object? onlyNotifyWhenFronting = null,Object? isPrivate = null,Object? currentStreak = null,Object? bestStreak = null,Object? totalCompletions = null,}) {
  return _then(_Habit(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,icon: freezed == icon ? _self.icon : icon // ignore: cast_nullable_to_non_nullable
as String?,colorHex: freezed == colorHex ? _self.colorHex : colorHex // ignore: cast_nullable_to_non_nullable
as String?,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,modifiedAt: null == modifiedAt ? _self.modifiedAt : modifiedAt // ignore: cast_nullable_to_non_nullable
as DateTime,frequency: null == frequency ? _self.frequency : frequency // ignore: cast_nullable_to_non_nullable
as HabitFrequency,weeklyDays: freezed == weeklyDays ? _self._weeklyDays : weeklyDays // ignore: cast_nullable_to_non_nullable
as List<int>?,intervalDays: freezed == intervalDays ? _self.intervalDays : intervalDays // ignore: cast_nullable_to_non_nullable
as int?,reminderTime: freezed == reminderTime ? _self.reminderTime : reminderTime // ignore: cast_nullable_to_non_nullable
as String?,notificationsEnabled: null == notificationsEnabled ? _self.notificationsEnabled : notificationsEnabled // ignore: cast_nullable_to_non_nullable
as bool,notificationMessage: freezed == notificationMessage ? _self.notificationMessage : notificationMessage // ignore: cast_nullable_to_non_nullable
as String?,assignedMemberId: freezed == assignedMemberId ? _self.assignedMemberId : assignedMemberId // ignore: cast_nullable_to_non_nullable
as String?,onlyNotifyWhenFronting: null == onlyNotifyWhenFronting ? _self.onlyNotifyWhenFronting : onlyNotifyWhenFronting // ignore: cast_nullable_to_non_nullable
as bool,isPrivate: null == isPrivate ? _self.isPrivate : isPrivate // ignore: cast_nullable_to_non_nullable
as bool,currentStreak: null == currentStreak ? _self.currentStreak : currentStreak // ignore: cast_nullable_to_non_nullable
as int,bestStreak: null == bestStreak ? _self.bestStreak : bestStreak // ignore: cast_nullable_to_non_nullable
as int,totalCompletions: null == totalCompletions ? _self.totalCompletions : totalCompletions // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
