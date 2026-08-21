// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'storage_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SavedProductItem {

 String get productId; String get name; String get brand; double get lowestPrice; String get imageUrl; DateTime get savedAt; bool get isSynced;
/// Create a copy of SavedProductItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SavedProductItemCopyWith<SavedProductItem> get copyWith => _$SavedProductItemCopyWithImpl<SavedProductItem>(this as SavedProductItem, _$identity);

  /// Serializes this SavedProductItem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SavedProductItem&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.name, name) || other.name == name)&&(identical(other.brand, brand) || other.brand == brand)&&(identical(other.lowestPrice, lowestPrice) || other.lowestPrice == lowestPrice)&&(identical(other.imageUrl, imageUrl) || other.imageUrl == imageUrl)&&(identical(other.savedAt, savedAt) || other.savedAt == savedAt)&&(identical(other.isSynced, isSynced) || other.isSynced == isSynced));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,productId,name,brand,lowestPrice,imageUrl,savedAt,isSynced);

@override
String toString() {
  return 'SavedProductItem(productId: $productId, name: $name, brand: $brand, lowestPrice: $lowestPrice, imageUrl: $imageUrl, savedAt: $savedAt, isSynced: $isSynced)';
}


}

/// @nodoc
abstract mixin class $SavedProductItemCopyWith<$Res>  {
  factory $SavedProductItemCopyWith(SavedProductItem value, $Res Function(SavedProductItem) _then) = _$SavedProductItemCopyWithImpl;
@useResult
$Res call({
 String productId, String name, String brand, double lowestPrice, String imageUrl, DateTime savedAt, bool isSynced
});




}
/// @nodoc
class _$SavedProductItemCopyWithImpl<$Res>
    implements $SavedProductItemCopyWith<$Res> {
  _$SavedProductItemCopyWithImpl(this._self, this._then);

  final SavedProductItem _self;
  final $Res Function(SavedProductItem) _then;

/// Create a copy of SavedProductItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? productId = null,Object? name = null,Object? brand = null,Object? lowestPrice = null,Object? imageUrl = null,Object? savedAt = null,Object? isSynced = null,}) {
  return _then(SavedProductItem(
productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,brand: null == brand ? _self.brand : brand // ignore: cast_nullable_to_non_nullable
as String,lowestPrice: null == lowestPrice ? _self.lowestPrice : lowestPrice // ignore: cast_nullable_to_non_nullable
as double,imageUrl: null == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String,savedAt: null == savedAt ? _self.savedAt : savedAt // ignore: cast_nullable_to_non_nullable
as DateTime,isSynced: null == isSynced ? _self.isSynced : isSynced // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [SavedProductItem].
extension SavedProductItemPatterns on SavedProductItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SavedProductItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SavedProductItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SavedProductItem value)  $default,){
final _that = this;
switch (_that) {
case _SavedProductItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SavedProductItem value)?  $default,){
final _that = this;
switch (_that) {
case _SavedProductItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String productId,  String name,  String brand,  double lowestPrice,  String imageUrl,  DateTime savedAt,  bool isSynced)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SavedProductItem() when $default != null:
return $default(_that.productId,_that.name,_that.brand,_that.lowestPrice,_that.imageUrl,_that.savedAt,_that.isSynced);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String productId,  String name,  String brand,  double lowestPrice,  String imageUrl,  DateTime savedAt,  bool isSynced)  $default,) {final _that = this;
switch (_that) {
case _SavedProductItem():
return $default(_that.productId,_that.name,_that.brand,_that.lowestPrice,_that.imageUrl,_that.savedAt,_that.isSynced);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String productId,  String name,  String brand,  double lowestPrice,  String imageUrl,  DateTime savedAt,  bool isSynced)?  $default,) {final _that = this;
switch (_that) {
case _SavedProductItem() when $default != null:
return $default(_that.productId,_that.name,_that.brand,_that.lowestPrice,_that.imageUrl,_that.savedAt,_that.isSynced);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SavedProductItem implements SavedProductItem {
  const _SavedProductItem({required this.productId, required this.name, required this.brand, required this.lowestPrice, required this.imageUrl, required this.savedAt, this.isSynced = false});
  factory _SavedProductItem.fromJson(Map<String, dynamic> json) => _$SavedProductItemFromJson(json);

@override final  String productId;
@override final  String name;
@override final  String brand;
@override final  double lowestPrice;
@override final  String imageUrl;
@override final  DateTime savedAt;
@override@JsonKey() final  bool isSynced;

/// Create a copy of SavedProductItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SavedProductItemCopyWith<_SavedProductItem> get copyWith => __$SavedProductItemCopyWithImpl<_SavedProductItem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SavedProductItemToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SavedProductItem&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.name, name) || other.name == name)&&(identical(other.brand, brand) || other.brand == brand)&&(identical(other.lowestPrice, lowestPrice) || other.lowestPrice == lowestPrice)&&(identical(other.imageUrl, imageUrl) || other.imageUrl == imageUrl)&&(identical(other.savedAt, savedAt) || other.savedAt == savedAt)&&(identical(other.isSynced, isSynced) || other.isSynced == isSynced));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,productId,name,brand,lowestPrice,imageUrl,savedAt,isSynced);

@override
String toString() {
  return 'SavedProductItem(productId: $productId, name: $name, brand: $brand, lowestPrice: $lowestPrice, imageUrl: $imageUrl, savedAt: $savedAt, isSynced: $isSynced)';
}


}

/// @nodoc
abstract mixin class _$SavedProductItemCopyWith<$Res> implements $SavedProductItemCopyWith<$Res> {
  factory _$SavedProductItemCopyWith(_SavedProductItem value, $Res Function(_SavedProductItem) _then) = __$SavedProductItemCopyWithImpl;
@override @useResult
$Res call({
 String productId, String name, String brand, double lowestPrice, String imageUrl, DateTime savedAt, bool isSynced
});




}
/// @nodoc
class __$SavedProductItemCopyWithImpl<$Res>
    implements _$SavedProductItemCopyWith<$Res> {
  __$SavedProductItemCopyWithImpl(this._self, this._then);

  final _SavedProductItem _self;
  final $Res Function(_SavedProductItem) _then;

/// Create a copy of SavedProductItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? productId = null,Object? name = null,Object? brand = null,Object? lowestPrice = null,Object? imageUrl = null,Object? savedAt = null,Object? isSynced = null,}) {
  return _then(_SavedProductItem(
productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,brand: null == brand ? _self.brand : brand // ignore: cast_nullable_to_non_nullable
as String,lowestPrice: null == lowestPrice ? _self.lowestPrice : lowestPrice // ignore: cast_nullable_to_non_nullable
as double,imageUrl: null == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String,savedAt: null == savedAt ? _self.savedAt : savedAt // ignore: cast_nullable_to_non_nullable
as DateTime,isSynced: null == isSynced ? _self.isSynced : isSynced // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$SavedShopItem {

 String get shopId; String get name; String get address; String get imageUrl; double get rating; DateTime get savedAt; bool get isSynced;
/// Create a copy of SavedShopItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SavedShopItemCopyWith<SavedShopItem> get copyWith => _$SavedShopItemCopyWithImpl<SavedShopItem>(this as SavedShopItem, _$identity);

  /// Serializes this SavedShopItem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SavedShopItem&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.name, name) || other.name == name)&&(identical(other.address, address) || other.address == address)&&(identical(other.imageUrl, imageUrl) || other.imageUrl == imageUrl)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.savedAt, savedAt) || other.savedAt == savedAt)&&(identical(other.isSynced, isSynced) || other.isSynced == isSynced));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,shopId,name,address,imageUrl,rating,savedAt,isSynced);

@override
String toString() {
  return 'SavedShopItem(shopId: $shopId, name: $name, address: $address, imageUrl: $imageUrl, rating: $rating, savedAt: $savedAt, isSynced: $isSynced)';
}


}

/// @nodoc
abstract mixin class $SavedShopItemCopyWith<$Res>  {
  factory $SavedShopItemCopyWith(SavedShopItem value, $Res Function(SavedShopItem) _then) = _$SavedShopItemCopyWithImpl;
@useResult
$Res call({
 String shopId, String name, String address, String imageUrl, double rating, DateTime savedAt, bool isSynced
});




}
/// @nodoc
class _$SavedShopItemCopyWithImpl<$Res>
    implements $SavedShopItemCopyWith<$Res> {
  _$SavedShopItemCopyWithImpl(this._self, this._then);

  final SavedShopItem _self;
  final $Res Function(SavedShopItem) _then;

/// Create a copy of SavedShopItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? shopId = null,Object? name = null,Object? address = null,Object? imageUrl = null,Object? rating = null,Object? savedAt = null,Object? isSynced = null,}) {
  return _then(SavedShopItem(
shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,imageUrl: null == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double,savedAt: null == savedAt ? _self.savedAt : savedAt // ignore: cast_nullable_to_non_nullable
as DateTime,isSynced: null == isSynced ? _self.isSynced : isSynced // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [SavedShopItem].
extension SavedShopItemPatterns on SavedShopItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SavedShopItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SavedShopItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SavedShopItem value)  $default,){
final _that = this;
switch (_that) {
case _SavedShopItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SavedShopItem value)?  $default,){
final _that = this;
switch (_that) {
case _SavedShopItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String shopId,  String name,  String address,  String imageUrl,  double rating,  DateTime savedAt,  bool isSynced)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SavedShopItem() when $default != null:
return $default(_that.shopId,_that.name,_that.address,_that.imageUrl,_that.rating,_that.savedAt,_that.isSynced);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String shopId,  String name,  String address,  String imageUrl,  double rating,  DateTime savedAt,  bool isSynced)  $default,) {final _that = this;
switch (_that) {
case _SavedShopItem():
return $default(_that.shopId,_that.name,_that.address,_that.imageUrl,_that.rating,_that.savedAt,_that.isSynced);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String shopId,  String name,  String address,  String imageUrl,  double rating,  DateTime savedAt,  bool isSynced)?  $default,) {final _that = this;
switch (_that) {
case _SavedShopItem() when $default != null:
return $default(_that.shopId,_that.name,_that.address,_that.imageUrl,_that.rating,_that.savedAt,_that.isSynced);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SavedShopItem implements SavedShopItem {
  const _SavedShopItem({required this.shopId, required this.name, required this.address, required this.imageUrl, required this.rating, required this.savedAt, this.isSynced = false});
  factory _SavedShopItem.fromJson(Map<String, dynamic> json) => _$SavedShopItemFromJson(json);

@override final  String shopId;
@override final  String name;
@override final  String address;
@override final  String imageUrl;
@override final  double rating;
@override final  DateTime savedAt;
@override@JsonKey() final  bool isSynced;

/// Create a copy of SavedShopItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SavedShopItemCopyWith<_SavedShopItem> get copyWith => __$SavedShopItemCopyWithImpl<_SavedShopItem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SavedShopItemToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SavedShopItem&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.name, name) || other.name == name)&&(identical(other.address, address) || other.address == address)&&(identical(other.imageUrl, imageUrl) || other.imageUrl == imageUrl)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.savedAt, savedAt) || other.savedAt == savedAt)&&(identical(other.isSynced, isSynced) || other.isSynced == isSynced));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,shopId,name,address,imageUrl,rating,savedAt,isSynced);

@override
String toString() {
  return 'SavedShopItem(shopId: $shopId, name: $name, address: $address, imageUrl: $imageUrl, rating: $rating, savedAt: $savedAt, isSynced: $isSynced)';
}


}

/// @nodoc
abstract mixin class _$SavedShopItemCopyWith<$Res> implements $SavedShopItemCopyWith<$Res> {
  factory _$SavedShopItemCopyWith(_SavedShopItem value, $Res Function(_SavedShopItem) _then) = __$SavedShopItemCopyWithImpl;
@override @useResult
$Res call({
 String shopId, String name, String address, String imageUrl, double rating, DateTime savedAt, bool isSynced
});




}
/// @nodoc
class __$SavedShopItemCopyWithImpl<$Res>
    implements _$SavedShopItemCopyWith<$Res> {
  __$SavedShopItemCopyWithImpl(this._self, this._then);

  final _SavedShopItem _self;
  final $Res Function(_SavedShopItem) _then;

/// Create a copy of SavedShopItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? shopId = null,Object? name = null,Object? address = null,Object? imageUrl = null,Object? rating = null,Object? savedAt = null,Object? isSynced = null,}) {
  return _then(_SavedShopItem(
shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,imageUrl: null == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double,savedAt: null == savedAt ? _self.savedAt : savedAt // ignore: cast_nullable_to_non_nullable
as DateTime,isSynced: null == isSynced ? _self.isSynced : isSynced // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$RecentlyViewedItem {

 String get productId; String get name; String get imageUrl; double get price; DateTime get viewedAt;
/// Create a copy of RecentlyViewedItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecentlyViewedItemCopyWith<RecentlyViewedItem> get copyWith => _$RecentlyViewedItemCopyWithImpl<RecentlyViewedItem>(this as RecentlyViewedItem, _$identity);

  /// Serializes this RecentlyViewedItem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecentlyViewedItem&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.name, name) || other.name == name)&&(identical(other.imageUrl, imageUrl) || other.imageUrl == imageUrl)&&(identical(other.price, price) || other.price == price)&&(identical(other.viewedAt, viewedAt) || other.viewedAt == viewedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,productId,name,imageUrl,price,viewedAt);

@override
String toString() {
  return 'RecentlyViewedItem(productId: $productId, name: $name, imageUrl: $imageUrl, price: $price, viewedAt: $viewedAt)';
}


}

/// @nodoc
abstract mixin class $RecentlyViewedItemCopyWith<$Res>  {
  factory $RecentlyViewedItemCopyWith(RecentlyViewedItem value, $Res Function(RecentlyViewedItem) _then) = _$RecentlyViewedItemCopyWithImpl;
@useResult
$Res call({
 String productId, String name, String imageUrl, double price, DateTime viewedAt
});




}
/// @nodoc
class _$RecentlyViewedItemCopyWithImpl<$Res>
    implements $RecentlyViewedItemCopyWith<$Res> {
  _$RecentlyViewedItemCopyWithImpl(this._self, this._then);

  final RecentlyViewedItem _self;
  final $Res Function(RecentlyViewedItem) _then;

/// Create a copy of RecentlyViewedItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? productId = null,Object? name = null,Object? imageUrl = null,Object? price = null,Object? viewedAt = null,}) {
  return _then(RecentlyViewedItem(
productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,imageUrl: null == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,viewedAt: null == viewedAt ? _self.viewedAt : viewedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [RecentlyViewedItem].
extension RecentlyViewedItemPatterns on RecentlyViewedItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecentlyViewedItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecentlyViewedItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecentlyViewedItem value)  $default,){
final _that = this;
switch (_that) {
case _RecentlyViewedItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecentlyViewedItem value)?  $default,){
final _that = this;
switch (_that) {
case _RecentlyViewedItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String productId,  String name,  String imageUrl,  double price,  DateTime viewedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecentlyViewedItem() when $default != null:
return $default(_that.productId,_that.name,_that.imageUrl,_that.price,_that.viewedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String productId,  String name,  String imageUrl,  double price,  DateTime viewedAt)  $default,) {final _that = this;
switch (_that) {
case _RecentlyViewedItem():
return $default(_that.productId,_that.name,_that.imageUrl,_that.price,_that.viewedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String productId,  String name,  String imageUrl,  double price,  DateTime viewedAt)?  $default,) {final _that = this;
switch (_that) {
case _RecentlyViewedItem() when $default != null:
return $default(_that.productId,_that.name,_that.imageUrl,_that.price,_that.viewedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RecentlyViewedItem implements RecentlyViewedItem {
  const _RecentlyViewedItem({required this.productId, required this.name, required this.imageUrl, required this.price, required this.viewedAt});
  factory _RecentlyViewedItem.fromJson(Map<String, dynamic> json) => _$RecentlyViewedItemFromJson(json);

@override final  String productId;
@override final  String name;
@override final  String imageUrl;
@override final  double price;
@override final  DateTime viewedAt;

/// Create a copy of RecentlyViewedItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecentlyViewedItemCopyWith<_RecentlyViewedItem> get copyWith => __$RecentlyViewedItemCopyWithImpl<_RecentlyViewedItem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RecentlyViewedItemToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecentlyViewedItem&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.name, name) || other.name == name)&&(identical(other.imageUrl, imageUrl) || other.imageUrl == imageUrl)&&(identical(other.price, price) || other.price == price)&&(identical(other.viewedAt, viewedAt) || other.viewedAt == viewedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,productId,name,imageUrl,price,viewedAt);

@override
String toString() {
  return 'RecentlyViewedItem(productId: $productId, name: $name, imageUrl: $imageUrl, price: $price, viewedAt: $viewedAt)';
}


}

/// @nodoc
abstract mixin class _$RecentlyViewedItemCopyWith<$Res> implements $RecentlyViewedItemCopyWith<$Res> {
  factory _$RecentlyViewedItemCopyWith(_RecentlyViewedItem value, $Res Function(_RecentlyViewedItem) _then) = __$RecentlyViewedItemCopyWithImpl;
@override @useResult
$Res call({
 String productId, String name, String imageUrl, double price, DateTime viewedAt
});




}
/// @nodoc
class __$RecentlyViewedItemCopyWithImpl<$Res>
    implements _$RecentlyViewedItemCopyWith<$Res> {
  __$RecentlyViewedItemCopyWithImpl(this._self, this._then);

  final _RecentlyViewedItem _self;
  final $Res Function(_RecentlyViewedItem) _then;

/// Create a copy of RecentlyViewedItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? productId = null,Object? name = null,Object? imageUrl = null,Object? price = null,Object? viewedAt = null,}) {
  return _then(_RecentlyViewedItem(
productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,imageUrl: null == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,viewedAt: null == viewedAt ? _self.viewedAt : viewedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}


/// @nodoc
mixin _$RecentSearchItem {

 String get query; DateTime get searchedAt;
/// Create a copy of RecentSearchItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecentSearchItemCopyWith<RecentSearchItem> get copyWith => _$RecentSearchItemCopyWithImpl<RecentSearchItem>(this as RecentSearchItem, _$identity);

  /// Serializes this RecentSearchItem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecentSearchItem&&(identical(other.query, query) || other.query == query)&&(identical(other.searchedAt, searchedAt) || other.searchedAt == searchedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,query,searchedAt);

@override
String toString() {
  return 'RecentSearchItem(query: $query, searchedAt: $searchedAt)';
}


}

/// @nodoc
abstract mixin class $RecentSearchItemCopyWith<$Res>  {
  factory $RecentSearchItemCopyWith(RecentSearchItem value, $Res Function(RecentSearchItem) _then) = _$RecentSearchItemCopyWithImpl;
@useResult
$Res call({
 String query, DateTime searchedAt
});




}
/// @nodoc
class _$RecentSearchItemCopyWithImpl<$Res>
    implements $RecentSearchItemCopyWith<$Res> {
  _$RecentSearchItemCopyWithImpl(this._self, this._then);

  final RecentSearchItem _self;
  final $Res Function(RecentSearchItem) _then;

/// Create a copy of RecentSearchItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? query = null,Object? searchedAt = null,}) {
  return _then(RecentSearchItem(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,searchedAt: null == searchedAt ? _self.searchedAt : searchedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [RecentSearchItem].
extension RecentSearchItemPatterns on RecentSearchItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecentSearchItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecentSearchItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecentSearchItem value)  $default,){
final _that = this;
switch (_that) {
case _RecentSearchItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecentSearchItem value)?  $default,){
final _that = this;
switch (_that) {
case _RecentSearchItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String query,  DateTime searchedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecentSearchItem() when $default != null:
return $default(_that.query,_that.searchedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String query,  DateTime searchedAt)  $default,) {final _that = this;
switch (_that) {
case _RecentSearchItem():
return $default(_that.query,_that.searchedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String query,  DateTime searchedAt)?  $default,) {final _that = this;
switch (_that) {
case _RecentSearchItem() when $default != null:
return $default(_that.query,_that.searchedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RecentSearchItem implements RecentSearchItem {
  const _RecentSearchItem({required this.query, required this.searchedAt});
  factory _RecentSearchItem.fromJson(Map<String, dynamic> json) => _$RecentSearchItemFromJson(json);

@override final  String query;
@override final  DateTime searchedAt;

/// Create a copy of RecentSearchItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecentSearchItemCopyWith<_RecentSearchItem> get copyWith => __$RecentSearchItemCopyWithImpl<_RecentSearchItem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RecentSearchItemToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecentSearchItem&&(identical(other.query, query) || other.query == query)&&(identical(other.searchedAt, searchedAt) || other.searchedAt == searchedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,query,searchedAt);

@override
String toString() {
  return 'RecentSearchItem(query: $query, searchedAt: $searchedAt)';
}


}

/// @nodoc
abstract mixin class _$RecentSearchItemCopyWith<$Res> implements $RecentSearchItemCopyWith<$Res> {
  factory _$RecentSearchItemCopyWith(_RecentSearchItem value, $Res Function(_RecentSearchItem) _then) = __$RecentSearchItemCopyWithImpl;
@override @useResult
$Res call({
 String query, DateTime searchedAt
});




}
/// @nodoc
class __$RecentSearchItemCopyWithImpl<$Res>
    implements _$RecentSearchItemCopyWith<$Res> {
  __$RecentSearchItemCopyWithImpl(this._self, this._then);

  final _RecentSearchItem _self;
  final $Res Function(_RecentSearchItem) _then;

/// Create a copy of RecentSearchItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? query = null,Object? searchedAt = null,}) {
  return _then(_RecentSearchItem(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,searchedAt: null == searchedAt ? _self.searchedAt : searchedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
