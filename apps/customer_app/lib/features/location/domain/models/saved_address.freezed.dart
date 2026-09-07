// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'saved_address.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SavedAddress {

/// Stable unique ID (UUID) for this saved address.
 String get id;/// User-friendly label (e.g. "Home", "Work", "Grandma's House").
 String get label;/// The underlying location data.
 UserLocation get location;/// Whether this is the currently selected/active address.
 bool get isSelected;/// Epoch milliseconds when this address was saved.
@JsonKey(name: 'savedAtMs') int get savedAtMs;
/// Create a copy of SavedAddress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SavedAddressCopyWith<SavedAddress> get copyWith => _$SavedAddressCopyWithImpl<SavedAddress>(this as SavedAddress, _$identity);

  /// Serializes this SavedAddress to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SavedAddress&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.location, location) || other.location == location)&&(identical(other.isSelected, isSelected) || other.isSelected == isSelected)&&(identical(other.savedAtMs, savedAtMs) || other.savedAtMs == savedAtMs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,label,location,isSelected,savedAtMs);

@override
String toString() {
  return 'SavedAddress(id: $id, label: $label, location: $location, isSelected: $isSelected, savedAtMs: $savedAtMs)';
}


}

/// @nodoc
abstract mixin class $SavedAddressCopyWith<$Res>  {
  factory $SavedAddressCopyWith(SavedAddress value, $Res Function(SavedAddress) _then) = _$SavedAddressCopyWithImpl;
@useResult
$Res call({
 String id, String label, UserLocation location, bool isSelected,@JsonKey(name: 'savedAtMs') int savedAtMs
});


$UserLocationCopyWith<$Res> get location;

}
/// @nodoc
class _$SavedAddressCopyWithImpl<$Res>
    implements $SavedAddressCopyWith<$Res> {
  _$SavedAddressCopyWithImpl(this._self, this._then);

  final SavedAddress _self;
  final $Res Function(SavedAddress) _then;

/// Create a copy of SavedAddress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,Object? location = null,Object? isSelected = null,Object? savedAtMs = null,}) {
  return _then(SavedAddress(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,location: null == location ? _self.location : location // ignore: cast_nullable_to_non_nullable
as UserLocation,isSelected: null == isSelected ? _self.isSelected : isSelected // ignore: cast_nullable_to_non_nullable
as bool,savedAtMs: null == savedAtMs ? _self.savedAtMs : savedAtMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of SavedAddress
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UserLocationCopyWith<$Res> get location {
  
  return $UserLocationCopyWith<$Res>(_self.location, (value) {
    return _then(_self.copyWith(location: value));
  });
}
}


/// Adds pattern-matching-related methods to [SavedAddress].
extension SavedAddressPatterns on SavedAddress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SavedAddress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SavedAddress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SavedAddress value)  $default,){
final _that = this;
switch (_that) {
case _SavedAddress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SavedAddress value)?  $default,){
final _that = this;
switch (_that) {
case _SavedAddress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String label,  UserLocation location,  bool isSelected, @JsonKey(name: 'savedAtMs')  int savedAtMs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SavedAddress() when $default != null:
return $default(_that.id,_that.label,_that.location,_that.isSelected,_that.savedAtMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String label,  UserLocation location,  bool isSelected, @JsonKey(name: 'savedAtMs')  int savedAtMs)  $default,) {final _that = this;
switch (_that) {
case _SavedAddress():
return $default(_that.id,_that.label,_that.location,_that.isSelected,_that.savedAtMs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String label,  UserLocation location,  bool isSelected, @JsonKey(name: 'savedAtMs')  int savedAtMs)?  $default,) {final _that = this;
switch (_that) {
case _SavedAddress() when $default != null:
return $default(_that.id,_that.label,_that.location,_that.isSelected,_that.savedAtMs);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SavedAddress extends SavedAddress {
  const _SavedAddress({required this.id, required this.label, required this.location, this.isSelected = false, @JsonKey(name: 'savedAtMs') this.savedAtMs = 0}): super._();
  factory _SavedAddress.fromJson(Map<String, dynamic> json) => _$SavedAddressFromJson(json);

/// Stable unique ID (UUID) for this saved address.
@override final  String id;
/// User-friendly label (e.g. "Home", "Work", "Grandma's House").
@override final  String label;
/// The underlying location data.
@override final  UserLocation location;
/// Whether this is the currently selected/active address.
@override@JsonKey() final  bool isSelected;
/// Epoch milliseconds when this address was saved.
@override@JsonKey(name: 'savedAtMs') final  int savedAtMs;

/// Create a copy of SavedAddress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SavedAddressCopyWith<_SavedAddress> get copyWith => __$SavedAddressCopyWithImpl<_SavedAddress>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SavedAddressToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SavedAddress&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.location, location) || other.location == location)&&(identical(other.isSelected, isSelected) || other.isSelected == isSelected)&&(identical(other.savedAtMs, savedAtMs) || other.savedAtMs == savedAtMs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,label,location,isSelected,savedAtMs);

@override
String toString() {
  return 'SavedAddress(id: $id, label: $label, location: $location, isSelected: $isSelected, savedAtMs: $savedAtMs)';
}


}

/// @nodoc
abstract mixin class _$SavedAddressCopyWith<$Res> implements $SavedAddressCopyWith<$Res> {
  factory _$SavedAddressCopyWith(_SavedAddress value, $Res Function(_SavedAddress) _then) = __$SavedAddressCopyWithImpl;
@override @useResult
$Res call({
 String id, String label, UserLocation location, bool isSelected,@JsonKey(name: 'savedAtMs') int savedAtMs
});


@override $UserLocationCopyWith<$Res> get location;

}
/// @nodoc
class __$SavedAddressCopyWithImpl<$Res>
    implements _$SavedAddressCopyWith<$Res> {
  __$SavedAddressCopyWithImpl(this._self, this._then);

  final _SavedAddress _self;
  final $Res Function(_SavedAddress) _then;

/// Create a copy of SavedAddress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,Object? location = null,Object? isSelected = null,Object? savedAtMs = null,}) {
  return _then(_SavedAddress(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,location: null == location ? _self.location : location // ignore: cast_nullable_to_non_nullable
as UserLocation,isSelected: null == isSelected ? _self.isSelected : isSelected // ignore: cast_nullable_to_non_nullable
as bool,savedAtMs: null == savedAtMs ? _self.savedAtMs : savedAtMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of SavedAddress
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UserLocationCopyWith<$Res> get location {
  
  return $UserLocationCopyWith<$Res>(_self.location, (value) {
    return _then(_self.copyWith(location: value));
  });
}
}

// dart format on
