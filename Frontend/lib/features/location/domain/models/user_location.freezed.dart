// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user_location.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$UserLocation {

 double get latitude; double get longitude;/// Human-readable address (e.g. "123 MG Road, Aayakar Bhawan").
 String get address;/// City / locality name.
 String get city;/// State / province name.
 String get state;/// Postal code (PIN code).
 String get pincode;/// Convenience label (e.g. "Home", "Work", "Patna Center").
/// Falls back to `city` when empty.
 String get label;/// True when the user manually picked this location
/// (instead of it coming from the device GPS).
 bool get isManual;/// True when coordinates are approximate (e.g. city-centre fallback
/// when reverse geocoding failed or GPS accuracy is low).
 bool get isApproximate;/// GPS accuracy in meters (0 = unknown).
 double get accuracyMeters;/// Whether this is the currently selected/active location.
 bool get isSelected;/// Epoch milliseconds when this location was captured.
@JsonKey(name: 'capturedAtMs') int get capturedAtMs;
/// Create a copy of UserLocation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserLocationCopyWith<UserLocation> get copyWith => _$UserLocationCopyWithImpl<UserLocation>(this as UserLocation, _$identity);

  /// Serializes this UserLocation to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserLocation&&(identical(other.latitude, latitude) || other.latitude == latitude)&&(identical(other.longitude, longitude) || other.longitude == longitude)&&(identical(other.address, address) || other.address == address)&&(identical(other.city, city) || other.city == city)&&(identical(other.state, state) || other.state == state)&&(identical(other.pincode, pincode) || other.pincode == pincode)&&(identical(other.label, label) || other.label == label)&&(identical(other.isManual, isManual) || other.isManual == isManual)&&(identical(other.isApproximate, isApproximate) || other.isApproximate == isApproximate)&&(identical(other.accuracyMeters, accuracyMeters) || other.accuracyMeters == accuracyMeters)&&(identical(other.isSelected, isSelected) || other.isSelected == isSelected)&&(identical(other.capturedAtMs, capturedAtMs) || other.capturedAtMs == capturedAtMs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,latitude,longitude,address,city,state,pincode,label,isManual,isApproximate,accuracyMeters,isSelected,capturedAtMs);

@override
String toString() {
  return 'UserLocation(latitude: $latitude, longitude: $longitude, address: $address, city: $city, state: $state, pincode: $pincode, label: $label, isManual: $isManual, isApproximate: $isApproximate, accuracyMeters: $accuracyMeters, isSelected: $isSelected, capturedAtMs: $capturedAtMs)';
}


}

/// @nodoc
abstract mixin class $UserLocationCopyWith<$Res>  {
  factory $UserLocationCopyWith(UserLocation value, $Res Function(UserLocation) _then) = _$UserLocationCopyWithImpl;
@useResult
$Res call({
 double latitude, double longitude, String address, String city, String state, String pincode, String label, bool isManual, bool isApproximate, double accuracyMeters, bool isSelected,@JsonKey(name: 'capturedAtMs') int capturedAtMs
});




}
/// @nodoc
class _$UserLocationCopyWithImpl<$Res>
    implements $UserLocationCopyWith<$Res> {
  _$UserLocationCopyWithImpl(this._self, this._then);

  final UserLocation _self;
  final $Res Function(UserLocation) _then;

/// Create a copy of UserLocation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? latitude = null,Object? longitude = null,Object? address = null,Object? city = null,Object? state = null,Object? pincode = null,Object? label = null,Object? isManual = null,Object? isApproximate = null,Object? accuracyMeters = null,Object? isSelected = null,Object? capturedAtMs = null,}) {
  return _then(UserLocation(
latitude: null == latitude ? _self.latitude : latitude // ignore: cast_nullable_to_non_nullable
as double,longitude: null == longitude ? _self.longitude : longitude // ignore: cast_nullable_to_non_nullable
as double,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,city: null == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,pincode: null == pincode ? _self.pincode : pincode // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,isManual: null == isManual ? _self.isManual : isManual // ignore: cast_nullable_to_non_nullable
as bool,isApproximate: null == isApproximate ? _self.isApproximate : isApproximate // ignore: cast_nullable_to_non_nullable
as bool,accuracyMeters: null == accuracyMeters ? _self.accuracyMeters : accuracyMeters // ignore: cast_nullable_to_non_nullable
as double,isSelected: null == isSelected ? _self.isSelected : isSelected // ignore: cast_nullable_to_non_nullable
as bool,capturedAtMs: null == capturedAtMs ? _self.capturedAtMs : capturedAtMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [UserLocation].
extension UserLocationPatterns on UserLocation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UserLocation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UserLocation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UserLocation value)  $default,){
final _that = this;
switch (_that) {
case _UserLocation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UserLocation value)?  $default,){
final _that = this;
switch (_that) {
case _UserLocation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( double latitude,  double longitude,  String address,  String city,  String state,  String pincode,  String label,  bool isManual,  bool isApproximate,  double accuracyMeters,  bool isSelected, @JsonKey(name: 'capturedAtMs')  int capturedAtMs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UserLocation() when $default != null:
return $default(_that.latitude,_that.longitude,_that.address,_that.city,_that.state,_that.pincode,_that.label,_that.isManual,_that.isApproximate,_that.accuracyMeters,_that.isSelected,_that.capturedAtMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( double latitude,  double longitude,  String address,  String city,  String state,  String pincode,  String label,  bool isManual,  bool isApproximate,  double accuracyMeters,  bool isSelected, @JsonKey(name: 'capturedAtMs')  int capturedAtMs)  $default,) {final _that = this;
switch (_that) {
case _UserLocation():
return $default(_that.latitude,_that.longitude,_that.address,_that.city,_that.state,_that.pincode,_that.label,_that.isManual,_that.isApproximate,_that.accuracyMeters,_that.isSelected,_that.capturedAtMs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( double latitude,  double longitude,  String address,  String city,  String state,  String pincode,  String label,  bool isManual,  bool isApproximate,  double accuracyMeters,  bool isSelected, @JsonKey(name: 'capturedAtMs')  int capturedAtMs)?  $default,) {final _that = this;
switch (_that) {
case _UserLocation() when $default != null:
return $default(_that.latitude,_that.longitude,_that.address,_that.city,_that.state,_that.pincode,_that.label,_that.isManual,_that.isApproximate,_that.accuracyMeters,_that.isSelected,_that.capturedAtMs);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _UserLocation extends UserLocation {
  const _UserLocation({required this.latitude, required this.longitude, this.address = '', this.city = '', this.state = '', this.pincode = '', this.label = '', this.isManual = false, this.isApproximate = false, this.accuracyMeters = 0.0, this.isSelected = false, @JsonKey(name: 'capturedAtMs') this.capturedAtMs = 0}): super._();
  factory _UserLocation.fromJson(Map<String, dynamic> json) => _$UserLocationFromJson(json);

@override final  double latitude;
@override final  double longitude;
/// Human-readable address (e.g. "123 MG Road, Aayakar Bhawan").
@override@JsonKey() final  String address;
/// City / locality name.
@override@JsonKey() final  String city;
/// State / province name.
@override@JsonKey() final  String state;
/// Postal code (PIN code).
@override@JsonKey() final  String pincode;
/// Convenience label (e.g. "Home", "Work", "Patna Center").
/// Falls back to `city` when empty.
@override@JsonKey() final  String label;
/// True when the user manually picked this location
/// (instead of it coming from the device GPS).
@override@JsonKey() final  bool isManual;
/// True when coordinates are approximate (e.g. city-centre fallback
/// when reverse geocoding failed or GPS accuracy is low).
@override@JsonKey() final  bool isApproximate;
/// GPS accuracy in meters (0 = unknown).
@override@JsonKey() final  double accuracyMeters;
/// Whether this is the currently selected/active location.
@override@JsonKey() final  bool isSelected;
/// Epoch milliseconds when this location was captured.
@override@JsonKey(name: 'capturedAtMs') final  int capturedAtMs;

/// Create a copy of UserLocation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UserLocationCopyWith<_UserLocation> get copyWith => __$UserLocationCopyWithImpl<_UserLocation>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$UserLocationToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UserLocation&&(identical(other.latitude, latitude) || other.latitude == latitude)&&(identical(other.longitude, longitude) || other.longitude == longitude)&&(identical(other.address, address) || other.address == address)&&(identical(other.city, city) || other.city == city)&&(identical(other.state, state) || other.state == state)&&(identical(other.pincode, pincode) || other.pincode == pincode)&&(identical(other.label, label) || other.label == label)&&(identical(other.isManual, isManual) || other.isManual == isManual)&&(identical(other.isApproximate, isApproximate) || other.isApproximate == isApproximate)&&(identical(other.accuracyMeters, accuracyMeters) || other.accuracyMeters == accuracyMeters)&&(identical(other.isSelected, isSelected) || other.isSelected == isSelected)&&(identical(other.capturedAtMs, capturedAtMs) || other.capturedAtMs == capturedAtMs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,latitude,longitude,address,city,state,pincode,label,isManual,isApproximate,accuracyMeters,isSelected,capturedAtMs);

@override
String toString() {
  return 'UserLocation(latitude: $latitude, longitude: $longitude, address: $address, city: $city, state: $state, pincode: $pincode, label: $label, isManual: $isManual, isApproximate: $isApproximate, accuracyMeters: $accuracyMeters, isSelected: $isSelected, capturedAtMs: $capturedAtMs)';
}


}

/// @nodoc
abstract mixin class _$UserLocationCopyWith<$Res> implements $UserLocationCopyWith<$Res> {
  factory _$UserLocationCopyWith(_UserLocation value, $Res Function(_UserLocation) _then) = __$UserLocationCopyWithImpl;
@override @useResult
$Res call({
 double latitude, double longitude, String address, String city, String state, String pincode, String label, bool isManual, bool isApproximate, double accuracyMeters, bool isSelected,@JsonKey(name: 'capturedAtMs') int capturedAtMs
});




}
/// @nodoc
class __$UserLocationCopyWithImpl<$Res>
    implements _$UserLocationCopyWith<$Res> {
  __$UserLocationCopyWithImpl(this._self, this._then);

  final _UserLocation _self;
  final $Res Function(_UserLocation) _then;

/// Create a copy of UserLocation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? latitude = null,Object? longitude = null,Object? address = null,Object? city = null,Object? state = null,Object? pincode = null,Object? label = null,Object? isManual = null,Object? isApproximate = null,Object? accuracyMeters = null,Object? isSelected = null,Object? capturedAtMs = null,}) {
  return _then(_UserLocation(
latitude: null == latitude ? _self.latitude : latitude // ignore: cast_nullable_to_non_nullable
as double,longitude: null == longitude ? _self.longitude : longitude // ignore: cast_nullable_to_non_nullable
as double,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,city: null == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,pincode: null == pincode ? _self.pincode : pincode // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,isManual: null == isManual ? _self.isManual : isManual // ignore: cast_nullable_to_non_nullable
as bool,isApproximate: null == isApproximate ? _self.isApproximate : isApproximate // ignore: cast_nullable_to_non_nullable
as bool,accuracyMeters: null == accuracyMeters ? _self.accuracyMeters : accuracyMeters // ignore: cast_nullable_to_non_nullable
as double,isSelected: null == isSelected ? _self.isSelected : isSelected // ignore: cast_nullable_to_non_nullable
as bool,capturedAtMs: null == capturedAtMs ? _self.capturedAtMs : capturedAtMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
