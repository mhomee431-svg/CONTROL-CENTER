// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'product_details_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ProductAttribute {

 String get name; List<String> get values;
/// Create a copy of ProductAttribute
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductAttributeCopyWith<ProductAttribute> get copyWith => _$ProductAttributeCopyWithImpl<ProductAttribute>(this as ProductAttribute, _$identity);

  /// Serializes this ProductAttribute to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductAttribute&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.values, values));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,const DeepCollectionEquality().hash(values));

@override
String toString() {
  return 'ProductAttribute(name: $name, values: $values)';
}


}

/// @nodoc
abstract mixin class $ProductAttributeCopyWith<$Res>  {
  factory $ProductAttributeCopyWith(ProductAttribute value, $Res Function(ProductAttribute) _then) = _$ProductAttributeCopyWithImpl;
@useResult
$Res call({
 String name, List<String> values
});




}
/// @nodoc
class _$ProductAttributeCopyWithImpl<$Res>
    implements $ProductAttributeCopyWith<$Res> {
  _$ProductAttributeCopyWithImpl(this._self, this._then);

  final ProductAttribute _self;
  final $Res Function(ProductAttribute) _then;

/// Create a copy of ProductAttribute
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? values = null,}) {
  return _then(ProductAttribute(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,values: null == values ? _self.values : values // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductAttribute].
extension ProductAttributePatterns on ProductAttribute {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductAttribute value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductAttribute() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductAttribute value)  $default,){
final _that = this;
switch (_that) {
case _ProductAttribute():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductAttribute value)?  $default,){
final _that = this;
switch (_that) {
case _ProductAttribute() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  List<String> values)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductAttribute() when $default != null:
return $default(_that.name,_that.values);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  List<String> values)  $default,) {final _that = this;
switch (_that) {
case _ProductAttribute():
return $default(_that.name,_that.values);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  List<String> values)?  $default,) {final _that = this;
switch (_that) {
case _ProductAttribute() when $default != null:
return $default(_that.name,_that.values);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProductAttribute implements ProductAttribute {
  const _ProductAttribute({required this.name, required  List<String> values}): _values = values;
  factory _ProductAttribute.fromJson(Map<String, dynamic> json) => _$ProductAttributeFromJson(json);

@override final  String name;
 final  List<String> _values;
@override List<String> get values {
  if (_values is EqualUnmodifiableListView) return _values;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_values);
}


/// Create a copy of ProductAttribute
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductAttributeCopyWith<_ProductAttribute> get copyWith => __$ProductAttributeCopyWithImpl<_ProductAttribute>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProductAttributeToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductAttribute&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other._values, _values));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,const DeepCollectionEquality().hash(_values));

@override
String toString() {
  return 'ProductAttribute(name: $name, values: $values)';
}


}

/// @nodoc
abstract mixin class _$ProductAttributeCopyWith<$Res> implements $ProductAttributeCopyWith<$Res> {
  factory _$ProductAttributeCopyWith(_ProductAttribute value, $Res Function(_ProductAttribute) _then) = __$ProductAttributeCopyWithImpl;
@override @useResult
$Res call({
 String name, List<String> values
});




}
/// @nodoc
class __$ProductAttributeCopyWithImpl<$Res>
    implements _$ProductAttributeCopyWith<$Res> {
  __$ProductAttributeCopyWithImpl(this._self, this._then);

  final _ProductAttribute _self;
  final $Res Function(_ProductAttribute) _then;

/// Create a copy of ProductAttribute
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? values = null,}) {
  return _then(_ProductAttribute(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,values: null == values ? _self._values : values // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}


/// @nodoc
mixin _$ProductIdentifier {

 String get type; String get value; bool get isPrimary;
/// Create a copy of ProductIdentifier
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductIdentifierCopyWith<ProductIdentifier> get copyWith => _$ProductIdentifierCopyWithImpl<ProductIdentifier>(this as ProductIdentifier, _$identity);

  /// Serializes this ProductIdentifier to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductIdentifier&&(identical(other.type, type) || other.type == type)&&(identical(other.value, value) || other.value == value)&&(identical(other.isPrimary, isPrimary) || other.isPrimary == isPrimary));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,value,isPrimary);

@override
String toString() {
  return 'ProductIdentifier(type: $type, value: $value, isPrimary: $isPrimary)';
}


}

/// @nodoc
abstract mixin class $ProductIdentifierCopyWith<$Res>  {
  factory $ProductIdentifierCopyWith(ProductIdentifier value, $Res Function(ProductIdentifier) _then) = _$ProductIdentifierCopyWithImpl;
@useResult
$Res call({
 String type, String value, bool isPrimary
});




}
/// @nodoc
class _$ProductIdentifierCopyWithImpl<$Res>
    implements $ProductIdentifierCopyWith<$Res> {
  _$ProductIdentifierCopyWithImpl(this._self, this._then);

  final ProductIdentifier _self;
  final $Res Function(ProductIdentifier) _then;

/// Create a copy of ProductIdentifier
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? value = null,Object? isPrimary = null,}) {
  return _then(ProductIdentifier(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,isPrimary: null == isPrimary ? _self.isPrimary : isPrimary // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductIdentifier].
extension ProductIdentifierPatterns on ProductIdentifier {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductIdentifier value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductIdentifier() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductIdentifier value)  $default,){
final _that = this;
switch (_that) {
case _ProductIdentifier():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductIdentifier value)?  $default,){
final _that = this;
switch (_that) {
case _ProductIdentifier() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String type,  String value,  bool isPrimary)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductIdentifier() when $default != null:
return $default(_that.type,_that.value,_that.isPrimary);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String type,  String value,  bool isPrimary)  $default,) {final _that = this;
switch (_that) {
case _ProductIdentifier():
return $default(_that.type,_that.value,_that.isPrimary);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String type,  String value,  bool isPrimary)?  $default,) {final _that = this;
switch (_that) {
case _ProductIdentifier() when $default != null:
return $default(_that.type,_that.value,_that.isPrimary);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProductIdentifier implements ProductIdentifier {
  const _ProductIdentifier({required this.type, required this.value, this.isPrimary = false});
  factory _ProductIdentifier.fromJson(Map<String, dynamic> json) => _$ProductIdentifierFromJson(json);

@override final  String type;
@override final  String value;
@override@JsonKey() final  bool isPrimary;

/// Create a copy of ProductIdentifier
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductIdentifierCopyWith<_ProductIdentifier> get copyWith => __$ProductIdentifierCopyWithImpl<_ProductIdentifier>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProductIdentifierToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductIdentifier&&(identical(other.type, type) || other.type == type)&&(identical(other.value, value) || other.value == value)&&(identical(other.isPrimary, isPrimary) || other.isPrimary == isPrimary));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,value,isPrimary);

@override
String toString() {
  return 'ProductIdentifier(type: $type, value: $value, isPrimary: $isPrimary)';
}


}

/// @nodoc
abstract mixin class _$ProductIdentifierCopyWith<$Res> implements $ProductIdentifierCopyWith<$Res> {
  factory _$ProductIdentifierCopyWith(_ProductIdentifier value, $Res Function(_ProductIdentifier) _then) = __$ProductIdentifierCopyWithImpl;
@override @useResult
$Res call({
 String type, String value, bool isPrimary
});




}
/// @nodoc
class __$ProductIdentifierCopyWithImpl<$Res>
    implements _$ProductIdentifierCopyWith<$Res> {
  __$ProductIdentifierCopyWithImpl(this._self, this._then);

  final _ProductIdentifier _self;
  final $Res Function(_ProductIdentifier) _then;

/// Create a copy of ProductIdentifier
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? value = null,Object? isPrimary = null,}) {
  return _then(_ProductIdentifier(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,isPrimary: null == isPrimary ? _self.isPrimary : isPrimary // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$ProductVariant {

 String get id; String get name; String? get sku; String? get description; Map<String, String> get attributes;
/// Create a copy of ProductVariant
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductVariantCopyWith<ProductVariant> get copyWith => _$ProductVariantCopyWithImpl<ProductVariant>(this as ProductVariant, _$identity);

  /// Serializes this ProductVariant to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductVariant&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.sku, sku) || other.sku == sku)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.attributes, attributes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,sku,description,const DeepCollectionEquality().hash(attributes));

@override
String toString() {
  return 'ProductVariant(id: $id, name: $name, sku: $sku, description: $description, attributes: $attributes)';
}


}

/// @nodoc
abstract mixin class $ProductVariantCopyWith<$Res>  {
  factory $ProductVariantCopyWith(ProductVariant value, $Res Function(ProductVariant) _then) = _$ProductVariantCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? sku, String? description, Map<String, String> attributes
});




}
/// @nodoc
class _$ProductVariantCopyWithImpl<$Res>
    implements $ProductVariantCopyWith<$Res> {
  _$ProductVariantCopyWithImpl(this._self, this._then);

  final ProductVariant _self;
  final $Res Function(ProductVariant) _then;

/// Create a copy of ProductVariant
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? sku = freezed,Object? description = freezed,Object? attributes = null,}) {
  return _then(ProductVariant(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sku: freezed == sku ? _self.sku : sku // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,attributes: null == attributes ? _self.attributes : attributes // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductVariant].
extension ProductVariantPatterns on ProductVariant {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductVariant value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductVariant() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductVariant value)  $default,){
final _that = this;
switch (_that) {
case _ProductVariant():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductVariant value)?  $default,){
final _that = this;
switch (_that) {
case _ProductVariant() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? sku,  String? description,  Map<String, String> attributes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductVariant() when $default != null:
return $default(_that.id,_that.name,_that.sku,_that.description,_that.attributes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? sku,  String? description,  Map<String, String> attributes)  $default,) {final _that = this;
switch (_that) {
case _ProductVariant():
return $default(_that.id,_that.name,_that.sku,_that.description,_that.attributes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? sku,  String? description,  Map<String, String> attributes)?  $default,) {final _that = this;
switch (_that) {
case _ProductVariant() when $default != null:
return $default(_that.id,_that.name,_that.sku,_that.description,_that.attributes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProductVariant implements ProductVariant {
  const _ProductVariant({required this.id, required this.name, this.sku, this.description,  Map<String, String> attributes = const <String, String>{}}): _attributes = attributes;
  factory _ProductVariant.fromJson(Map<String, dynamic> json) => _$ProductVariantFromJson(json);

@override final  String id;
@override final  String name;
@override final  String? sku;
@override final  String? description;
 final  Map<String, String> _attributes;
@override@JsonKey() Map<String, String> get attributes {
  if (_attributes is EqualUnmodifiableMapView) return _attributes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_attributes);
}


/// Create a copy of ProductVariant
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductVariantCopyWith<_ProductVariant> get copyWith => __$ProductVariantCopyWithImpl<_ProductVariant>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProductVariantToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductVariant&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.sku, sku) || other.sku == sku)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other._attributes, _attributes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,sku,description,const DeepCollectionEquality().hash(_attributes));

@override
String toString() {
  return 'ProductVariant(id: $id, name: $name, sku: $sku, description: $description, attributes: $attributes)';
}


}

/// @nodoc
abstract mixin class _$ProductVariantCopyWith<$Res> implements $ProductVariantCopyWith<$Res> {
  factory _$ProductVariantCopyWith(_ProductVariant value, $Res Function(_ProductVariant) _then) = __$ProductVariantCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? sku, String? description, Map<String, String> attributes
});




}
/// @nodoc
class __$ProductVariantCopyWithImpl<$Res>
    implements _$ProductVariantCopyWith<$Res> {
  __$ProductVariantCopyWithImpl(this._self, this._then);

  final _ProductVariant _self;
  final $Res Function(_ProductVariant) _then;

/// Create a copy of ProductVariant
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? sku = freezed,Object? description = freezed,Object? attributes = null,}) {
  return _then(_ProductVariant(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sku: freezed == sku ? _self.sku : sku // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,attributes: null == attributes ? _self._attributes : attributes // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}


/// @nodoc
mixin _$ProductMasterDetails {

 String get id; String get name; String get brand; String get category; String? get subcategory; String? get description; String? get shortDescription; String? get baseUnit; double? get baseQuantity; double? get mrp; String? get priceRange; List<String> get imageUrls; List<ProductVariant> get variants; List<ProductAttribute> get attributes; List<ProductIdentifier> get identifiers; bool get isSaved;
/// Create a copy of ProductMasterDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductMasterDetailsCopyWith<ProductMasterDetails> get copyWith => _$ProductMasterDetailsCopyWithImpl<ProductMasterDetails>(this as ProductMasterDetails, _$identity);

  /// Serializes this ProductMasterDetails to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductMasterDetails&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.brand, brand) || other.brand == brand)&&(identical(other.category, category) || other.category == category)&&(identical(other.subcategory, subcategory) || other.subcategory == subcategory)&&(identical(other.description, description) || other.description == description)&&(identical(other.shortDescription, shortDescription) || other.shortDescription == shortDescription)&&(identical(other.baseUnit, baseUnit) || other.baseUnit == baseUnit)&&(identical(other.baseQuantity, baseQuantity) || other.baseQuantity == baseQuantity)&&(identical(other.mrp, mrp) || other.mrp == mrp)&&(identical(other.priceRange, priceRange) || other.priceRange == priceRange)&&const DeepCollectionEquality().equals(other.imageUrls, imageUrls)&&const DeepCollectionEquality().equals(other.variants, variants)&&const DeepCollectionEquality().equals(other.attributes, attributes)&&const DeepCollectionEquality().equals(other.identifiers, identifiers)&&(identical(other.isSaved, isSaved) || other.isSaved == isSaved));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,brand,category,subcategory,description,shortDescription,baseUnit,baseQuantity,mrp,priceRange,const DeepCollectionEquality().hash(imageUrls),const DeepCollectionEquality().hash(variants),const DeepCollectionEquality().hash(attributes),const DeepCollectionEquality().hash(identifiers),isSaved);

@override
String toString() {
  return 'ProductMasterDetails(id: $id, name: $name, brand: $brand, category: $category, subcategory: $subcategory, description: $description, shortDescription: $shortDescription, baseUnit: $baseUnit, baseQuantity: $baseQuantity, mrp: $mrp, priceRange: $priceRange, imageUrls: $imageUrls, variants: $variants, attributes: $attributes, identifiers: $identifiers, isSaved: $isSaved)';
}


}

/// @nodoc
abstract mixin class $ProductMasterDetailsCopyWith<$Res>  {
  factory $ProductMasterDetailsCopyWith(ProductMasterDetails value, $Res Function(ProductMasterDetails) _then) = _$ProductMasterDetailsCopyWithImpl;
@useResult
$Res call({
 String id, String name, String brand, String category, String? subcategory, String? description, String? shortDescription, String? baseUnit, double? baseQuantity, double? mrp, String? priceRange, List<String> imageUrls, List<ProductVariant> variants, List<ProductAttribute> attributes, List<ProductIdentifier> identifiers, bool isSaved
});




}
/// @nodoc
class _$ProductMasterDetailsCopyWithImpl<$Res>
    implements $ProductMasterDetailsCopyWith<$Res> {
  _$ProductMasterDetailsCopyWithImpl(this._self, this._then);

  final ProductMasterDetails _self;
  final $Res Function(ProductMasterDetails) _then;

/// Create a copy of ProductMasterDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? brand = null,Object? category = null,Object? subcategory = freezed,Object? description = freezed,Object? shortDescription = freezed,Object? baseUnit = freezed,Object? baseQuantity = freezed,Object? mrp = freezed,Object? priceRange = freezed,Object? imageUrls = null,Object? variants = null,Object? attributes = null,Object? identifiers = null,Object? isSaved = null,}) {
  return _then(ProductMasterDetails(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,brand: null == brand ? _self.brand : brand // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,subcategory: freezed == subcategory ? _self.subcategory : subcategory // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,shortDescription: freezed == shortDescription ? _self.shortDescription : shortDescription // ignore: cast_nullable_to_non_nullable
as String?,baseUnit: freezed == baseUnit ? _self.baseUnit : baseUnit // ignore: cast_nullable_to_non_nullable
as String?,baseQuantity: freezed == baseQuantity ? _self.baseQuantity : baseQuantity // ignore: cast_nullable_to_non_nullable
as double?,mrp: freezed == mrp ? _self.mrp : mrp // ignore: cast_nullable_to_non_nullable
as double?,priceRange: freezed == priceRange ? _self.priceRange : priceRange // ignore: cast_nullable_to_non_nullable
as String?,imageUrls: null == imageUrls ? _self.imageUrls : imageUrls // ignore: cast_nullable_to_non_nullable
as List<String>,variants: null == variants ? _self.variants : variants // ignore: cast_nullable_to_non_nullable
as List<ProductVariant>,attributes: null == attributes ? _self.attributes : attributes // ignore: cast_nullable_to_non_nullable
as List<ProductAttribute>,identifiers: null == identifiers ? _self.identifiers : identifiers // ignore: cast_nullable_to_non_nullable
as List<ProductIdentifier>,isSaved: null == isSaved ? _self.isSaved : isSaved // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductMasterDetails].
extension ProductMasterDetailsPatterns on ProductMasterDetails {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductMasterDetails value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductMasterDetails() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductMasterDetails value)  $default,){
final _that = this;
switch (_that) {
case _ProductMasterDetails():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductMasterDetails value)?  $default,){
final _that = this;
switch (_that) {
case _ProductMasterDetails() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String brand,  String category,  String? subcategory,  String? description,  String? shortDescription,  String? baseUnit,  double? baseQuantity,  double? mrp,  String? priceRange,  List<String> imageUrls,  List<ProductVariant> variants,  List<ProductAttribute> attributes,  List<ProductIdentifier> identifiers,  bool isSaved)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductMasterDetails() when $default != null:
return $default(_that.id,_that.name,_that.brand,_that.category,_that.subcategory,_that.description,_that.shortDescription,_that.baseUnit,_that.baseQuantity,_that.mrp,_that.priceRange,_that.imageUrls,_that.variants,_that.attributes,_that.identifiers,_that.isSaved);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String brand,  String category,  String? subcategory,  String? description,  String? shortDescription,  String? baseUnit,  double? baseQuantity,  double? mrp,  String? priceRange,  List<String> imageUrls,  List<ProductVariant> variants,  List<ProductAttribute> attributes,  List<ProductIdentifier> identifiers,  bool isSaved)  $default,) {final _that = this;
switch (_that) {
case _ProductMasterDetails():
return $default(_that.id,_that.name,_that.brand,_that.category,_that.subcategory,_that.description,_that.shortDescription,_that.baseUnit,_that.baseQuantity,_that.mrp,_that.priceRange,_that.imageUrls,_that.variants,_that.attributes,_that.identifiers,_that.isSaved);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String brand,  String category,  String? subcategory,  String? description,  String? shortDescription,  String? baseUnit,  double? baseQuantity,  double? mrp,  String? priceRange,  List<String> imageUrls,  List<ProductVariant> variants,  List<ProductAttribute> attributes,  List<ProductIdentifier> identifiers,  bool isSaved)?  $default,) {final _that = this;
switch (_that) {
case _ProductMasterDetails() when $default != null:
return $default(_that.id,_that.name,_that.brand,_that.category,_that.subcategory,_that.description,_that.shortDescription,_that.baseUnit,_that.baseQuantity,_that.mrp,_that.priceRange,_that.imageUrls,_that.variants,_that.attributes,_that.identifiers,_that.isSaved);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProductMasterDetails implements ProductMasterDetails {
  const _ProductMasterDetails({required this.id, required this.name, required this.brand, required this.category, this.subcategory, this.description, this.shortDescription, this.baseUnit, this.baseQuantity, this.mrp, this.priceRange,  List<String> imageUrls = const <String>[],  List<ProductVariant> variants = const <ProductVariant>[],  List<ProductAttribute> attributes = const <ProductAttribute>[],  List<ProductIdentifier> identifiers = const <ProductIdentifier>[], this.isSaved = false}): _imageUrls = imageUrls,_variants = variants,_attributes = attributes,_identifiers = identifiers;
  factory _ProductMasterDetails.fromJson(Map<String, dynamic> json) => _$ProductMasterDetailsFromJson(json);

@override final  String id;
@override final  String name;
@override final  String brand;
@override final  String category;
@override final  String? subcategory;
@override final  String? description;
@override final  String? shortDescription;
@override final  String? baseUnit;
@override final  double? baseQuantity;
@override final  double? mrp;
@override final  String? priceRange;
 final  List<String> _imageUrls;
@override@JsonKey() List<String> get imageUrls {
  if (_imageUrls is EqualUnmodifiableListView) return _imageUrls;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_imageUrls);
}

 final  List<ProductVariant> _variants;
@override@JsonKey() List<ProductVariant> get variants {
  if (_variants is EqualUnmodifiableListView) return _variants;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_variants);
}

 final  List<ProductAttribute> _attributes;
@override@JsonKey() List<ProductAttribute> get attributes {
  if (_attributes is EqualUnmodifiableListView) return _attributes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_attributes);
}

 final  List<ProductIdentifier> _identifiers;
@override@JsonKey() List<ProductIdentifier> get identifiers {
  if (_identifiers is EqualUnmodifiableListView) return _identifiers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_identifiers);
}

@override@JsonKey() final  bool isSaved;

/// Create a copy of ProductMasterDetails
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductMasterDetailsCopyWith<_ProductMasterDetails> get copyWith => __$ProductMasterDetailsCopyWithImpl<_ProductMasterDetails>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProductMasterDetailsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductMasterDetails&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.brand, brand) || other.brand == brand)&&(identical(other.category, category) || other.category == category)&&(identical(other.subcategory, subcategory) || other.subcategory == subcategory)&&(identical(other.description, description) || other.description == description)&&(identical(other.shortDescription, shortDescription) || other.shortDescription == shortDescription)&&(identical(other.baseUnit, baseUnit) || other.baseUnit == baseUnit)&&(identical(other.baseQuantity, baseQuantity) || other.baseQuantity == baseQuantity)&&(identical(other.mrp, mrp) || other.mrp == mrp)&&(identical(other.priceRange, priceRange) || other.priceRange == priceRange)&&const DeepCollectionEquality().equals(other._imageUrls, _imageUrls)&&const DeepCollectionEquality().equals(other._variants, _variants)&&const DeepCollectionEquality().equals(other._attributes, _attributes)&&const DeepCollectionEquality().equals(other._identifiers, _identifiers)&&(identical(other.isSaved, isSaved) || other.isSaved == isSaved));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,brand,category,subcategory,description,shortDescription,baseUnit,baseQuantity,mrp,priceRange,const DeepCollectionEquality().hash(_imageUrls),const DeepCollectionEquality().hash(_variants),const DeepCollectionEquality().hash(_attributes),const DeepCollectionEquality().hash(_identifiers),isSaved);

@override
String toString() {
  return 'ProductMasterDetails(id: $id, name: $name, brand: $brand, category: $category, subcategory: $subcategory, description: $description, shortDescription: $shortDescription, baseUnit: $baseUnit, baseQuantity: $baseQuantity, mrp: $mrp, priceRange: $priceRange, imageUrls: $imageUrls, variants: $variants, attributes: $attributes, identifiers: $identifiers, isSaved: $isSaved)';
}


}

/// @nodoc
abstract mixin class _$ProductMasterDetailsCopyWith<$Res> implements $ProductMasterDetailsCopyWith<$Res> {
  factory _$ProductMasterDetailsCopyWith(_ProductMasterDetails value, $Res Function(_ProductMasterDetails) _then) = __$ProductMasterDetailsCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String brand, String category, String? subcategory, String? description, String? shortDescription, String? baseUnit, double? baseQuantity, double? mrp, String? priceRange, List<String> imageUrls, List<ProductVariant> variants, List<ProductAttribute> attributes, List<ProductIdentifier> identifiers, bool isSaved
});




}
/// @nodoc
class __$ProductMasterDetailsCopyWithImpl<$Res>
    implements _$ProductMasterDetailsCopyWith<$Res> {
  __$ProductMasterDetailsCopyWithImpl(this._self, this._then);

  final _ProductMasterDetails _self;
  final $Res Function(_ProductMasterDetails) _then;

/// Create a copy of ProductMasterDetails
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? brand = null,Object? category = null,Object? subcategory = freezed,Object? description = freezed,Object? shortDescription = freezed,Object? baseUnit = freezed,Object? baseQuantity = freezed,Object? mrp = freezed,Object? priceRange = freezed,Object? imageUrls = null,Object? variants = null,Object? attributes = null,Object? identifiers = null,Object? isSaved = null,}) {
  return _then(_ProductMasterDetails(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,brand: null == brand ? _self.brand : brand // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,subcategory: freezed == subcategory ? _self.subcategory : subcategory // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,shortDescription: freezed == shortDescription ? _self.shortDescription : shortDescription // ignore: cast_nullable_to_non_nullable
as String?,baseUnit: freezed == baseUnit ? _self.baseUnit : baseUnit // ignore: cast_nullable_to_non_nullable
as String?,baseQuantity: freezed == baseQuantity ? _self.baseQuantity : baseQuantity // ignore: cast_nullable_to_non_nullable
as double?,mrp: freezed == mrp ? _self.mrp : mrp // ignore: cast_nullable_to_non_nullable
as double?,priceRange: freezed == priceRange ? _self.priceRange : priceRange // ignore: cast_nullable_to_non_nullable
as String?,imageUrls: null == imageUrls ? _self._imageUrls : imageUrls // ignore: cast_nullable_to_non_nullable
as List<String>,variants: null == variants ? _self._variants : variants // ignore: cast_nullable_to_non_nullable
as List<ProductVariant>,attributes: null == attributes ? _self._attributes : attributes // ignore: cast_nullable_to_non_nullable
as List<ProductAttribute>,identifiers: null == identifiers ? _self._identifiers : identifiers // ignore: cast_nullable_to_non_nullable
as List<ProductIdentifier>,isSaved: null == isSaved ? _self.isSaved : isSaved // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$ShopInventoryOffer {

 String get shopId; String get shopName; String get shopImageUrl; double get price; double? get mrp; double get distanceInKm; double get rating; bool get isAvailable; DateTime get lastUpdated; String? get stockStatus; String? get freshnessStatus; String? get offerText;/// Whether the shop is open right now, per the backend's opening-hours
/// evaluation. Null means the backend did not report it (unknown) and must
/// never be rendered as "Open".
 bool? get isOpenNow;/// Whether the shop is currently accepting orders. Null = unknown.
 bool? get isAcceptingOrders;
/// Create a copy of ShopInventoryOffer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShopInventoryOfferCopyWith<ShopInventoryOffer> get copyWith => _$ShopInventoryOfferCopyWithImpl<ShopInventoryOffer>(this as ShopInventoryOffer, _$identity);

  /// Serializes this ShopInventoryOffer to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShopInventoryOffer&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.shopName, shopName) || other.shopName == shopName)&&(identical(other.shopImageUrl, shopImageUrl) || other.shopImageUrl == shopImageUrl)&&(identical(other.price, price) || other.price == price)&&(identical(other.mrp, mrp) || other.mrp == mrp)&&(identical(other.distanceInKm, distanceInKm) || other.distanceInKm == distanceInKm)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.isAvailable, isAvailable) || other.isAvailable == isAvailable)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated)&&(identical(other.stockStatus, stockStatus) || other.stockStatus == stockStatus)&&(identical(other.freshnessStatus, freshnessStatus) || other.freshnessStatus == freshnessStatus)&&(identical(other.offerText, offerText) || other.offerText == offerText)&&(identical(other.isOpenNow, isOpenNow) || other.isOpenNow == isOpenNow)&&(identical(other.isAcceptingOrders, isAcceptingOrders) || other.isAcceptingOrders == isAcceptingOrders));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,shopId,shopName,shopImageUrl,price,mrp,distanceInKm,rating,isAvailable,lastUpdated,stockStatus,freshnessStatus,offerText,isOpenNow,isAcceptingOrders);

@override
String toString() {
  return 'ShopInventoryOffer(shopId: $shopId, shopName: $shopName, shopImageUrl: $shopImageUrl, price: $price, mrp: $mrp, distanceInKm: $distanceInKm, rating: $rating, isAvailable: $isAvailable, lastUpdated: $lastUpdated, stockStatus: $stockStatus, freshnessStatus: $freshnessStatus, offerText: $offerText, isOpenNow: $isOpenNow, isAcceptingOrders: $isAcceptingOrders)';
}


}

/// @nodoc
abstract mixin class $ShopInventoryOfferCopyWith<$Res>  {
  factory $ShopInventoryOfferCopyWith(ShopInventoryOffer value, $Res Function(ShopInventoryOffer) _then) = _$ShopInventoryOfferCopyWithImpl;
@useResult
$Res call({
 String shopId, String shopName, String shopImageUrl, double price, double? mrp, double distanceInKm, double rating, bool isAvailable, DateTime lastUpdated, String? stockStatus, String? freshnessStatus, String? offerText, bool? isOpenNow, bool? isAcceptingOrders
});




}
/// @nodoc
class _$ShopInventoryOfferCopyWithImpl<$Res>
    implements $ShopInventoryOfferCopyWith<$Res> {
  _$ShopInventoryOfferCopyWithImpl(this._self, this._then);

  final ShopInventoryOffer _self;
  final $Res Function(ShopInventoryOffer) _then;

/// Create a copy of ShopInventoryOffer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? shopId = null,Object? shopName = null,Object? shopImageUrl = null,Object? price = null,Object? mrp = freezed,Object? distanceInKm = null,Object? rating = null,Object? isAvailable = null,Object? lastUpdated = null,Object? stockStatus = freezed,Object? freshnessStatus = freezed,Object? offerText = freezed,Object? isOpenNow = freezed,Object? isAcceptingOrders = freezed,}) {
  return _then(ShopInventoryOffer(
shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,shopName: null == shopName ? _self.shopName : shopName // ignore: cast_nullable_to_non_nullable
as String,shopImageUrl: null == shopImageUrl ? _self.shopImageUrl : shopImageUrl // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,mrp: freezed == mrp ? _self.mrp : mrp // ignore: cast_nullable_to_non_nullable
as double?,distanceInKm: null == distanceInKm ? _self.distanceInKm : distanceInKm // ignore: cast_nullable_to_non_nullable
as double,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double,isAvailable: null == isAvailable ? _self.isAvailable : isAvailable // ignore: cast_nullable_to_non_nullable
as bool,lastUpdated: null == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as DateTime,stockStatus: freezed == stockStatus ? _self.stockStatus : stockStatus // ignore: cast_nullable_to_non_nullable
as String?,freshnessStatus: freezed == freshnessStatus ? _self.freshnessStatus : freshnessStatus // ignore: cast_nullable_to_non_nullable
as String?,offerText: freezed == offerText ? _self.offerText : offerText // ignore: cast_nullable_to_non_nullable
as String?,isOpenNow: freezed == isOpenNow ? _self.isOpenNow : isOpenNow // ignore: cast_nullable_to_non_nullable
as bool?,isAcceptingOrders: freezed == isAcceptingOrders ? _self.isAcceptingOrders : isAcceptingOrders // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [ShopInventoryOffer].
extension ShopInventoryOfferPatterns on ShopInventoryOffer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShopInventoryOffer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShopInventoryOffer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShopInventoryOffer value)  $default,){
final _that = this;
switch (_that) {
case _ShopInventoryOffer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShopInventoryOffer value)?  $default,){
final _that = this;
switch (_that) {
case _ShopInventoryOffer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String shopId,  String shopName,  String shopImageUrl,  double price,  double? mrp,  double distanceInKm,  double rating,  bool isAvailable,  DateTime lastUpdated,  String? stockStatus,  String? freshnessStatus,  String? offerText,  bool? isOpenNow,  bool? isAcceptingOrders)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShopInventoryOffer() when $default != null:
return $default(_that.shopId,_that.shopName,_that.shopImageUrl,_that.price,_that.mrp,_that.distanceInKm,_that.rating,_that.isAvailable,_that.lastUpdated,_that.stockStatus,_that.freshnessStatus,_that.offerText,_that.isOpenNow,_that.isAcceptingOrders);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String shopId,  String shopName,  String shopImageUrl,  double price,  double? mrp,  double distanceInKm,  double rating,  bool isAvailable,  DateTime lastUpdated,  String? stockStatus,  String? freshnessStatus,  String? offerText,  bool? isOpenNow,  bool? isAcceptingOrders)  $default,) {final _that = this;
switch (_that) {
case _ShopInventoryOffer():
return $default(_that.shopId,_that.shopName,_that.shopImageUrl,_that.price,_that.mrp,_that.distanceInKm,_that.rating,_that.isAvailable,_that.lastUpdated,_that.stockStatus,_that.freshnessStatus,_that.offerText,_that.isOpenNow,_that.isAcceptingOrders);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String shopId,  String shopName,  String shopImageUrl,  double price,  double? mrp,  double distanceInKm,  double rating,  bool isAvailable,  DateTime lastUpdated,  String? stockStatus,  String? freshnessStatus,  String? offerText,  bool? isOpenNow,  bool? isAcceptingOrders)?  $default,) {final _that = this;
switch (_that) {
case _ShopInventoryOffer() when $default != null:
return $default(_that.shopId,_that.shopName,_that.shopImageUrl,_that.price,_that.mrp,_that.distanceInKm,_that.rating,_that.isAvailable,_that.lastUpdated,_that.stockStatus,_that.freshnessStatus,_that.offerText,_that.isOpenNow,_that.isAcceptingOrders);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ShopInventoryOffer extends ShopInventoryOffer {
  const _ShopInventoryOffer({required this.shopId, required this.shopName, required this.shopImageUrl, required this.price, this.mrp, required this.distanceInKm, required this.rating, required this.isAvailable, required this.lastUpdated, this.stockStatus, this.freshnessStatus, this.offerText, this.isOpenNow, this.isAcceptingOrders}): super._();
  factory _ShopInventoryOffer.fromJson(Map<String, dynamic> json) => _$ShopInventoryOfferFromJson(json);

@override final  String shopId;
@override final  String shopName;
@override final  String shopImageUrl;
@override final  double price;
@override final  double? mrp;
@override final  double distanceInKm;
@override final  double rating;
@override final  bool isAvailable;
@override final  DateTime lastUpdated;
@override final  String? stockStatus;
@override final  String? freshnessStatus;
@override final  String? offerText;
/// Whether the shop is open right now, per the backend's opening-hours
/// evaluation. Null means the backend did not report it (unknown) and must
/// never be rendered as "Open".
@override final  bool? isOpenNow;
/// Whether the shop is currently accepting orders. Null = unknown.
@override final  bool? isAcceptingOrders;

/// Create a copy of ShopInventoryOffer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShopInventoryOfferCopyWith<_ShopInventoryOffer> get copyWith => __$ShopInventoryOfferCopyWithImpl<_ShopInventoryOffer>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ShopInventoryOfferToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShopInventoryOffer&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.shopName, shopName) || other.shopName == shopName)&&(identical(other.shopImageUrl, shopImageUrl) || other.shopImageUrl == shopImageUrl)&&(identical(other.price, price) || other.price == price)&&(identical(other.mrp, mrp) || other.mrp == mrp)&&(identical(other.distanceInKm, distanceInKm) || other.distanceInKm == distanceInKm)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.isAvailable, isAvailable) || other.isAvailable == isAvailable)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated)&&(identical(other.stockStatus, stockStatus) || other.stockStatus == stockStatus)&&(identical(other.freshnessStatus, freshnessStatus) || other.freshnessStatus == freshnessStatus)&&(identical(other.offerText, offerText) || other.offerText == offerText)&&(identical(other.isOpenNow, isOpenNow) || other.isOpenNow == isOpenNow)&&(identical(other.isAcceptingOrders, isAcceptingOrders) || other.isAcceptingOrders == isAcceptingOrders));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,shopId,shopName,shopImageUrl,price,mrp,distanceInKm,rating,isAvailable,lastUpdated,stockStatus,freshnessStatus,offerText,isOpenNow,isAcceptingOrders);

@override
String toString() {
  return 'ShopInventoryOffer(shopId: $shopId, shopName: $shopName, shopImageUrl: $shopImageUrl, price: $price, mrp: $mrp, distanceInKm: $distanceInKm, rating: $rating, isAvailable: $isAvailable, lastUpdated: $lastUpdated, stockStatus: $stockStatus, freshnessStatus: $freshnessStatus, offerText: $offerText, isOpenNow: $isOpenNow, isAcceptingOrders: $isAcceptingOrders)';
}


}

/// @nodoc
abstract mixin class _$ShopInventoryOfferCopyWith<$Res> implements $ShopInventoryOfferCopyWith<$Res> {
  factory _$ShopInventoryOfferCopyWith(_ShopInventoryOffer value, $Res Function(_ShopInventoryOffer) _then) = __$ShopInventoryOfferCopyWithImpl;
@override @useResult
$Res call({
 String shopId, String shopName, String shopImageUrl, double price, double? mrp, double distanceInKm, double rating, bool isAvailable, DateTime lastUpdated, String? stockStatus, String? freshnessStatus, String? offerText, bool? isOpenNow, bool? isAcceptingOrders
});




}
/// @nodoc
class __$ShopInventoryOfferCopyWithImpl<$Res>
    implements _$ShopInventoryOfferCopyWith<$Res> {
  __$ShopInventoryOfferCopyWithImpl(this._self, this._then);

  final _ShopInventoryOffer _self;
  final $Res Function(_ShopInventoryOffer) _then;

/// Create a copy of ShopInventoryOffer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? shopId = null,Object? shopName = null,Object? shopImageUrl = null,Object? price = null,Object? mrp = freezed,Object? distanceInKm = null,Object? rating = null,Object? isAvailable = null,Object? lastUpdated = null,Object? stockStatus = freezed,Object? freshnessStatus = freezed,Object? offerText = freezed,Object? isOpenNow = freezed,Object? isAcceptingOrders = freezed,}) {
  return _then(_ShopInventoryOffer(
shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,shopName: null == shopName ? _self.shopName : shopName // ignore: cast_nullable_to_non_nullable
as String,shopImageUrl: null == shopImageUrl ? _self.shopImageUrl : shopImageUrl // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,mrp: freezed == mrp ? _self.mrp : mrp // ignore: cast_nullable_to_non_nullable
as double?,distanceInKm: null == distanceInKm ? _self.distanceInKm : distanceInKm // ignore: cast_nullable_to_non_nullable
as double,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double,isAvailable: null == isAvailable ? _self.isAvailable : isAvailable // ignore: cast_nullable_to_non_nullable
as bool,lastUpdated: null == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as DateTime,stockStatus: freezed == stockStatus ? _self.stockStatus : stockStatus // ignore: cast_nullable_to_non_nullable
as String?,freshnessStatus: freezed == freshnessStatus ? _self.freshnessStatus : freshnessStatus // ignore: cast_nullable_to_non_nullable
as String?,offerText: freezed == offerText ? _self.offerText : offerText // ignore: cast_nullable_to_non_nullable
as String?,isOpenNow: freezed == isOpenNow ? _self.isOpenNow : isOpenNow // ignore: cast_nullable_to_non_nullable
as bool?,isAcceptingOrders: freezed == isAcceptingOrders ? _self.isAcceptingOrders : isAcceptingOrders // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}


/// @nodoc
mixin _$ProductDetails {

 ProductMasterDetails get product; List<ShopInventoryOffer> get shopOffers;/// Whether this payload came from the local cache rather than the network.
///
/// This is the field that stops the app from presenting old data as live.
/// Product master data (name, brand, images, description) is stable enough
/// to cache, so serving it offline is good behaviour — but only if the UI
/// says so. Without this flag a cached page is indistinguishable from a
/// fresh one, and the customer has no way to know the prices they are
/// looking at may be out of date.
 bool get servedFromCache;/// When this payload was cached. Null for live data.
///
/// Drives the "Last updated …" line. Null whenever [servedFromCache] is
/// false, because a live response is current by definition and dating it
/// would be noise.
 DateTime? get cachedAt;
/// Create a copy of ProductDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductDetailsCopyWith<ProductDetails> get copyWith => _$ProductDetailsCopyWithImpl<ProductDetails>(this as ProductDetails, _$identity);

  /// Serializes this ProductDetails to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductDetails&&(identical(other.product, product) || other.product == product)&&const DeepCollectionEquality().equals(other.shopOffers, shopOffers)&&(identical(other.servedFromCache, servedFromCache) || other.servedFromCache == servedFromCache)&&(identical(other.cachedAt, cachedAt) || other.cachedAt == cachedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,product,const DeepCollectionEquality().hash(shopOffers),servedFromCache,cachedAt);

@override
String toString() {
  return 'ProductDetails(product: $product, shopOffers: $shopOffers, servedFromCache: $servedFromCache, cachedAt: $cachedAt)';
}


}

/// @nodoc
abstract mixin class $ProductDetailsCopyWith<$Res>  {
  factory $ProductDetailsCopyWith(ProductDetails value, $Res Function(ProductDetails) _then) = _$ProductDetailsCopyWithImpl;
@useResult
$Res call({
 ProductMasterDetails product, List<ShopInventoryOffer> shopOffers, bool servedFromCache, DateTime? cachedAt
});


$ProductMasterDetailsCopyWith<$Res> get product;

}
/// @nodoc
class _$ProductDetailsCopyWithImpl<$Res>
    implements $ProductDetailsCopyWith<$Res> {
  _$ProductDetailsCopyWithImpl(this._self, this._then);

  final ProductDetails _self;
  final $Res Function(ProductDetails) _then;

/// Create a copy of ProductDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? product = null,Object? shopOffers = null,Object? servedFromCache = null,Object? cachedAt = freezed,}) {
  return _then(ProductDetails(
product: null == product ? _self.product : product // ignore: cast_nullable_to_non_nullable
as ProductMasterDetails,shopOffers: null == shopOffers ? _self.shopOffers : shopOffers // ignore: cast_nullable_to_non_nullable
as List<ShopInventoryOffer>,servedFromCache: null == servedFromCache ? _self.servedFromCache : servedFromCache // ignore: cast_nullable_to_non_nullable
as bool,cachedAt: freezed == cachedAt ? _self.cachedAt : cachedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of ProductDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductMasterDetailsCopyWith<$Res> get product {
  
  return $ProductMasterDetailsCopyWith<$Res>(_self.product, (value) {
    return _then(_self.copyWith(product: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProductDetails].
extension ProductDetailsPatterns on ProductDetails {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductDetails value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductDetails() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductDetails value)  $default,){
final _that = this;
switch (_that) {
case _ProductDetails():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductDetails value)?  $default,){
final _that = this;
switch (_that) {
case _ProductDetails() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductMasterDetails product,  List<ShopInventoryOffer> shopOffers,  bool servedFromCache,  DateTime? cachedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductDetails() when $default != null:
return $default(_that.product,_that.shopOffers,_that.servedFromCache,_that.cachedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductMasterDetails product,  List<ShopInventoryOffer> shopOffers,  bool servedFromCache,  DateTime? cachedAt)  $default,) {final _that = this;
switch (_that) {
case _ProductDetails():
return $default(_that.product,_that.shopOffers,_that.servedFromCache,_that.cachedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductMasterDetails product,  List<ShopInventoryOffer> shopOffers,  bool servedFromCache,  DateTime? cachedAt)?  $default,) {final _that = this;
switch (_that) {
case _ProductDetails() when $default != null:
return $default(_that.product,_that.shopOffers,_that.servedFromCache,_that.cachedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProductDetails extends ProductDetails {
  const _ProductDetails({required this.product,  List<ShopInventoryOffer> shopOffers = const <ShopInventoryOffer>[], this.servedFromCache = false, this.cachedAt}): _shopOffers = shopOffers,super._();
  factory _ProductDetails.fromJson(Map<String, dynamic> json) => _$ProductDetailsFromJson(json);

@override final  ProductMasterDetails product;
 final  List<ShopInventoryOffer> _shopOffers;
@override@JsonKey() List<ShopInventoryOffer> get shopOffers {
  if (_shopOffers is EqualUnmodifiableListView) return _shopOffers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_shopOffers);
}

/// Whether this payload came from the local cache rather than the network.
///
/// This is the field that stops the app from presenting old data as live.
/// Product master data (name, brand, images, description) is stable enough
/// to cache, so serving it offline is good behaviour — but only if the UI
/// says so. Without this flag a cached page is indistinguishable from a
/// fresh one, and the customer has no way to know the prices they are
/// looking at may be out of date.
@override@JsonKey() final  bool servedFromCache;
/// When this payload was cached. Null for live data.
///
/// Drives the "Last updated …" line. Null whenever [servedFromCache] is
/// false, because a live response is current by definition and dating it
/// would be noise.
@override final  DateTime? cachedAt;

/// Create a copy of ProductDetails
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductDetailsCopyWith<_ProductDetails> get copyWith => __$ProductDetailsCopyWithImpl<_ProductDetails>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProductDetailsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductDetails&&(identical(other.product, product) || other.product == product)&&const DeepCollectionEquality().equals(other._shopOffers, _shopOffers)&&(identical(other.servedFromCache, servedFromCache) || other.servedFromCache == servedFromCache)&&(identical(other.cachedAt, cachedAt) || other.cachedAt == cachedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,product,const DeepCollectionEquality().hash(_shopOffers),servedFromCache,cachedAt);

@override
String toString() {
  return 'ProductDetails(product: $product, shopOffers: $shopOffers, servedFromCache: $servedFromCache, cachedAt: $cachedAt)';
}


}

/// @nodoc
abstract mixin class _$ProductDetailsCopyWith<$Res> implements $ProductDetailsCopyWith<$Res> {
  factory _$ProductDetailsCopyWith(_ProductDetails value, $Res Function(_ProductDetails) _then) = __$ProductDetailsCopyWithImpl;
@override @useResult
$Res call({
 ProductMasterDetails product, List<ShopInventoryOffer> shopOffers, bool servedFromCache, DateTime? cachedAt
});


@override $ProductMasterDetailsCopyWith<$Res> get product;

}
/// @nodoc
class __$ProductDetailsCopyWithImpl<$Res>
    implements _$ProductDetailsCopyWith<$Res> {
  __$ProductDetailsCopyWithImpl(this._self, this._then);

  final _ProductDetails _self;
  final $Res Function(_ProductDetails) _then;

/// Create a copy of ProductDetails
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? product = null,Object? shopOffers = null,Object? servedFromCache = null,Object? cachedAt = freezed,}) {
  return _then(_ProductDetails(
product: null == product ? _self.product : product // ignore: cast_nullable_to_non_nullable
as ProductMasterDetails,shopOffers: null == shopOffers ? _self._shopOffers : shopOffers // ignore: cast_nullable_to_non_nullable
as List<ShopInventoryOffer>,servedFromCache: null == servedFromCache ? _self.servedFromCache : servedFromCache // ignore: cast_nullable_to_non_nullable
as bool,cachedAt: freezed == cachedAt ? _self.cachedAt : cachedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of ProductDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductMasterDetailsCopyWith<$Res> get product {
  
  return $ProductMasterDetailsCopyWith<$Res>(_self.product, (value) {
    return _then(_self.copyWith(product: value));
  });
}
}

// dart format on
