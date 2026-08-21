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
mixin _$ShopOffer {

 String get shopId; String get shopName; String get shopImageUrl; double get price; double get distanceInKm; double get rating; bool get isAvailable; DateTime get lastUpdated; String? get offerText;
/// Create a copy of ShopOffer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShopOfferCopyWith<ShopOffer> get copyWith => _$ShopOfferCopyWithImpl<ShopOffer>(this as ShopOffer, _$identity);

  /// Serializes this ShopOffer to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShopOffer&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.shopName, shopName) || other.shopName == shopName)&&(identical(other.shopImageUrl, shopImageUrl) || other.shopImageUrl == shopImageUrl)&&(identical(other.price, price) || other.price == price)&&(identical(other.distanceInKm, distanceInKm) || other.distanceInKm == distanceInKm)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.isAvailable, isAvailable) || other.isAvailable == isAvailable)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated)&&(identical(other.offerText, offerText) || other.offerText == offerText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,shopId,shopName,shopImageUrl,price,distanceInKm,rating,isAvailable,lastUpdated,offerText);

@override
String toString() {
  return 'ShopOffer(shopId: $shopId, shopName: $shopName, shopImageUrl: $shopImageUrl, price: $price, distanceInKm: $distanceInKm, rating: $rating, isAvailable: $isAvailable, lastUpdated: $lastUpdated, offerText: $offerText)';
}


}

/// @nodoc
abstract mixin class $ShopOfferCopyWith<$Res>  {
  factory $ShopOfferCopyWith(ShopOffer value, $Res Function(ShopOffer) _then) = _$ShopOfferCopyWithImpl;
@useResult
$Res call({
 String shopId, String shopName, String shopImageUrl, double price, double distanceInKm, double rating, bool isAvailable, DateTime lastUpdated, String? offerText
});




}
/// @nodoc
class _$ShopOfferCopyWithImpl<$Res>
    implements $ShopOfferCopyWith<$Res> {
  _$ShopOfferCopyWithImpl(this._self, this._then);

  final ShopOffer _self;
  final $Res Function(ShopOffer) _then;

/// Create a copy of ShopOffer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? shopId = null,Object? shopName = null,Object? shopImageUrl = null,Object? price = null,Object? distanceInKm = null,Object? rating = null,Object? isAvailable = null,Object? lastUpdated = null,Object? offerText = freezed,}) {
  return _then(ShopOffer(
shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,shopName: null == shopName ? _self.shopName : shopName // ignore: cast_nullable_to_non_nullable
as String,shopImageUrl: null == shopImageUrl ? _self.shopImageUrl : shopImageUrl // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,distanceInKm: null == distanceInKm ? _self.distanceInKm : distanceInKm // ignore: cast_nullable_to_non_nullable
as double,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double,isAvailable: null == isAvailable ? _self.isAvailable : isAvailable // ignore: cast_nullable_to_non_nullable
as bool,lastUpdated: null == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as DateTime,offerText: freezed == offerText ? _self.offerText : offerText // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ShopOffer].
extension ShopOfferPatterns on ShopOffer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShopOffer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShopOffer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShopOffer value)  $default,){
final _that = this;
switch (_that) {
case _ShopOffer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShopOffer value)?  $default,){
final _that = this;
switch (_that) {
case _ShopOffer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String shopId,  String shopName,  String shopImageUrl,  double price,  double distanceInKm,  double rating,  bool isAvailable,  DateTime lastUpdated,  String? offerText)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShopOffer() when $default != null:
return $default(_that.shopId,_that.shopName,_that.shopImageUrl,_that.price,_that.distanceInKm,_that.rating,_that.isAvailable,_that.lastUpdated,_that.offerText);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String shopId,  String shopName,  String shopImageUrl,  double price,  double distanceInKm,  double rating,  bool isAvailable,  DateTime lastUpdated,  String? offerText)  $default,) {final _that = this;
switch (_that) {
case _ShopOffer():
return $default(_that.shopId,_that.shopName,_that.shopImageUrl,_that.price,_that.distanceInKm,_that.rating,_that.isAvailable,_that.lastUpdated,_that.offerText);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String shopId,  String shopName,  String shopImageUrl,  double price,  double distanceInKm,  double rating,  bool isAvailable,  DateTime lastUpdated,  String? offerText)?  $default,) {final _that = this;
switch (_that) {
case _ShopOffer() when $default != null:
return $default(_that.shopId,_that.shopName,_that.shopImageUrl,_that.price,_that.distanceInKm,_that.rating,_that.isAvailable,_that.lastUpdated,_that.offerText);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ShopOffer implements ShopOffer {
  const _ShopOffer({required this.shopId, required this.shopName, required this.shopImageUrl, required this.price, required this.distanceInKm, required this.rating, required this.isAvailable, required this.lastUpdated, this.offerText});
  factory _ShopOffer.fromJson(Map<String, dynamic> json) => _$ShopOfferFromJson(json);

@override final  String shopId;
@override final  String shopName;
@override final  String shopImageUrl;
@override final  double price;
@override final  double distanceInKm;
@override final  double rating;
@override final  bool isAvailable;
@override final  DateTime lastUpdated;
@override final  String? offerText;

/// Create a copy of ShopOffer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShopOfferCopyWith<_ShopOffer> get copyWith => __$ShopOfferCopyWithImpl<_ShopOffer>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ShopOfferToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShopOffer&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.shopName, shopName) || other.shopName == shopName)&&(identical(other.shopImageUrl, shopImageUrl) || other.shopImageUrl == shopImageUrl)&&(identical(other.price, price) || other.price == price)&&(identical(other.distanceInKm, distanceInKm) || other.distanceInKm == distanceInKm)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.isAvailable, isAvailable) || other.isAvailable == isAvailable)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated)&&(identical(other.offerText, offerText) || other.offerText == offerText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,shopId,shopName,shopImageUrl,price,distanceInKm,rating,isAvailable,lastUpdated,offerText);

@override
String toString() {
  return 'ShopOffer(shopId: $shopId, shopName: $shopName, shopImageUrl: $shopImageUrl, price: $price, distanceInKm: $distanceInKm, rating: $rating, isAvailable: $isAvailable, lastUpdated: $lastUpdated, offerText: $offerText)';
}


}

/// @nodoc
abstract mixin class _$ShopOfferCopyWith<$Res> implements $ShopOfferCopyWith<$Res> {
  factory _$ShopOfferCopyWith(_ShopOffer value, $Res Function(_ShopOffer) _then) = __$ShopOfferCopyWithImpl;
@override @useResult
$Res call({
 String shopId, String shopName, String shopImageUrl, double price, double distanceInKm, double rating, bool isAvailable, DateTime lastUpdated, String? offerText
});




}
/// @nodoc
class __$ShopOfferCopyWithImpl<$Res>
    implements _$ShopOfferCopyWith<$Res> {
  __$ShopOfferCopyWithImpl(this._self, this._then);

  final _ShopOffer _self;
  final $Res Function(_ShopOffer) _then;

/// Create a copy of ShopOffer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? shopId = null,Object? shopName = null,Object? shopImageUrl = null,Object? price = null,Object? distanceInKm = null,Object? rating = null,Object? isAvailable = null,Object? lastUpdated = null,Object? offerText = freezed,}) {
  return _then(_ShopOffer(
shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,shopName: null == shopName ? _self.shopName : shopName // ignore: cast_nullable_to_non_nullable
as String,shopImageUrl: null == shopImageUrl ? _self.shopImageUrl : shopImageUrl // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,distanceInKm: null == distanceInKm ? _self.distanceInKm : distanceInKm // ignore: cast_nullable_to_non_nullable
as double,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double,isAvailable: null == isAvailable ? _self.isAvailable : isAvailable // ignore: cast_nullable_to_non_nullable
as bool,lastUpdated: null == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as DateTime,offerText: freezed == offerText ? _self.offerText : offerText // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$ProductDetails {

 String get id; String get name; String get brand; String get category; String get description; List<String> get imageUrls; String get priceRange; bool get isAvailableAnywhere; List<ShopOffer> get nearbyShopsOffers; bool get isSaved;
/// Create a copy of ProductDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductDetailsCopyWith<ProductDetails> get copyWith => _$ProductDetailsCopyWithImpl<ProductDetails>(this as ProductDetails, _$identity);

  /// Serializes this ProductDetails to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductDetails&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.brand, brand) || other.brand == brand)&&(identical(other.category, category) || other.category == category)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.imageUrls, imageUrls)&&(identical(other.priceRange, priceRange) || other.priceRange == priceRange)&&(identical(other.isAvailableAnywhere, isAvailableAnywhere) || other.isAvailableAnywhere == isAvailableAnywhere)&&const DeepCollectionEquality().equals(other.nearbyShopsOffers, nearbyShopsOffers)&&(identical(other.isSaved, isSaved) || other.isSaved == isSaved));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,brand,category,description,const DeepCollectionEquality().hash(imageUrls),priceRange,isAvailableAnywhere,const DeepCollectionEquality().hash(nearbyShopsOffers),isSaved);

@override
String toString() {
  return 'ProductDetails(id: $id, name: $name, brand: $brand, category: $category, description: $description, imageUrls: $imageUrls, priceRange: $priceRange, isAvailableAnywhere: $isAvailableAnywhere, nearbyShopsOffers: $nearbyShopsOffers, isSaved: $isSaved)';
}


}

/// @nodoc
abstract mixin class $ProductDetailsCopyWith<$Res>  {
  factory $ProductDetailsCopyWith(ProductDetails value, $Res Function(ProductDetails) _then) = _$ProductDetailsCopyWithImpl;
@useResult
$Res call({
 String id, String name, String brand, String category, String description, List<String> imageUrls, String priceRange, bool isAvailableAnywhere, List<ShopOffer> nearbyShopsOffers, bool isSaved
});




}
/// @nodoc
class _$ProductDetailsCopyWithImpl<$Res>
    implements $ProductDetailsCopyWith<$Res> {
  _$ProductDetailsCopyWithImpl(this._self, this._then);

  final ProductDetails _self;
  final $Res Function(ProductDetails) _then;

/// Create a copy of ProductDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? brand = null,Object? category = null,Object? description = null,Object? imageUrls = null,Object? priceRange = null,Object? isAvailableAnywhere = null,Object? nearbyShopsOffers = null,Object? isSaved = null,}) {
  return _then(ProductDetails(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,brand: null == brand ? _self.brand : brand // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,imageUrls: null == imageUrls ? _self.imageUrls : imageUrls // ignore: cast_nullable_to_non_nullable
as List<String>,priceRange: null == priceRange ? _self.priceRange : priceRange // ignore: cast_nullable_to_non_nullable
as String,isAvailableAnywhere: null == isAvailableAnywhere ? _self.isAvailableAnywhere : isAvailableAnywhere // ignore: cast_nullable_to_non_nullable
as bool,nearbyShopsOffers: null == nearbyShopsOffers ? _self.nearbyShopsOffers : nearbyShopsOffers // ignore: cast_nullable_to_non_nullable
as List<ShopOffer>,isSaved: null == isSaved ? _self.isSaved : isSaved // ignore: cast_nullable_to_non_nullable
as bool,
  ));
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String brand,  String category,  String description,  List<String> imageUrls,  String priceRange,  bool isAvailableAnywhere,  List<ShopOffer> nearbyShopsOffers,  bool isSaved)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductDetails() when $default != null:
return $default(_that.id,_that.name,_that.brand,_that.category,_that.description,_that.imageUrls,_that.priceRange,_that.isAvailableAnywhere,_that.nearbyShopsOffers,_that.isSaved);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String brand,  String category,  String description,  List<String> imageUrls,  String priceRange,  bool isAvailableAnywhere,  List<ShopOffer> nearbyShopsOffers,  bool isSaved)  $default,) {final _that = this;
switch (_that) {
case _ProductDetails():
return $default(_that.id,_that.name,_that.brand,_that.category,_that.description,_that.imageUrls,_that.priceRange,_that.isAvailableAnywhere,_that.nearbyShopsOffers,_that.isSaved);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String brand,  String category,  String description,  List<String> imageUrls,  String priceRange,  bool isAvailableAnywhere,  List<ShopOffer> nearbyShopsOffers,  bool isSaved)?  $default,) {final _that = this;
switch (_that) {
case _ProductDetails() when $default != null:
return $default(_that.id,_that.name,_that.brand,_that.category,_that.description,_that.imageUrls,_that.priceRange,_that.isAvailableAnywhere,_that.nearbyShopsOffers,_that.isSaved);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProductDetails implements ProductDetails {
  const _ProductDetails({required this.id, required this.name, required this.brand, required this.category, required this.description, required  List<String> imageUrls, required this.priceRange, required this.isAvailableAnywhere, required  List<ShopOffer> nearbyShopsOffers, this.isSaved = false}): _imageUrls = imageUrls,_nearbyShopsOffers = nearbyShopsOffers;
  factory _ProductDetails.fromJson(Map<String, dynamic> json) => _$ProductDetailsFromJson(json);

@override final  String id;
@override final  String name;
@override final  String brand;
@override final  String category;
@override final  String description;
 final  List<String> _imageUrls;
@override List<String> get imageUrls {
  if (_imageUrls is EqualUnmodifiableListView) return _imageUrls;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_imageUrls);
}

@override final  String priceRange;
@override final  bool isAvailableAnywhere;
 final  List<ShopOffer> _nearbyShopsOffers;
@override List<ShopOffer> get nearbyShopsOffers {
  if (_nearbyShopsOffers is EqualUnmodifiableListView) return _nearbyShopsOffers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_nearbyShopsOffers);
}

@override@JsonKey() final  bool isSaved;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductDetails&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.brand, brand) || other.brand == brand)&&(identical(other.category, category) || other.category == category)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other._imageUrls, _imageUrls)&&(identical(other.priceRange, priceRange) || other.priceRange == priceRange)&&(identical(other.isAvailableAnywhere, isAvailableAnywhere) || other.isAvailableAnywhere == isAvailableAnywhere)&&const DeepCollectionEquality().equals(other._nearbyShopsOffers, _nearbyShopsOffers)&&(identical(other.isSaved, isSaved) || other.isSaved == isSaved));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,brand,category,description,const DeepCollectionEquality().hash(_imageUrls),priceRange,isAvailableAnywhere,const DeepCollectionEquality().hash(_nearbyShopsOffers),isSaved);

@override
String toString() {
  return 'ProductDetails(id: $id, name: $name, brand: $brand, category: $category, description: $description, imageUrls: $imageUrls, priceRange: $priceRange, isAvailableAnywhere: $isAvailableAnywhere, nearbyShopsOffers: $nearbyShopsOffers, isSaved: $isSaved)';
}


}

/// @nodoc
abstract mixin class _$ProductDetailsCopyWith<$Res> implements $ProductDetailsCopyWith<$Res> {
  factory _$ProductDetailsCopyWith(_ProductDetails value, $Res Function(_ProductDetails) _then) = __$ProductDetailsCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String brand, String category, String description, List<String> imageUrls, String priceRange, bool isAvailableAnywhere, List<ShopOffer> nearbyShopsOffers, bool isSaved
});




}
/// @nodoc
class __$ProductDetailsCopyWithImpl<$Res>
    implements _$ProductDetailsCopyWith<$Res> {
  __$ProductDetailsCopyWithImpl(this._self, this._then);

  final _ProductDetails _self;
  final $Res Function(_ProductDetails) _then;

/// Create a copy of ProductDetails
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? brand = null,Object? category = null,Object? description = null,Object? imageUrls = null,Object? priceRange = null,Object? isAvailableAnywhere = null,Object? nearbyShopsOffers = null,Object? isSaved = null,}) {
  return _then(_ProductDetails(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,brand: null == brand ? _self.brand : brand // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,imageUrls: null == imageUrls ? _self._imageUrls : imageUrls // ignore: cast_nullable_to_non_nullable
as List<String>,priceRange: null == priceRange ? _self.priceRange : priceRange // ignore: cast_nullable_to_non_nullable
as String,isAvailableAnywhere: null == isAvailableAnywhere ? _self.isAvailableAnywhere : isAvailableAnywhere // ignore: cast_nullable_to_non_nullable
as bool,nearbyShopsOffers: null == nearbyShopsOffers ? _self._nearbyShopsOffers : nearbyShopsOffers // ignore: cast_nullable_to_non_nullable
as List<ShopOffer>,isSaved: null == isSaved ? _self.isSaved : isSaved // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
