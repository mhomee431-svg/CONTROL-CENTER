// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'search_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SearchSuggestion {

 String get text; bool get isCategory; bool get isBrand;
/// Create a copy of SearchSuggestion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SearchSuggestionCopyWith<SearchSuggestion> get copyWith => _$SearchSuggestionCopyWithImpl<SearchSuggestion>(this as SearchSuggestion, _$identity);

  /// Serializes this SearchSuggestion to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SearchSuggestion&&(identical(other.text, text) || other.text == text)&&(identical(other.isCategory, isCategory) || other.isCategory == isCategory)&&(identical(other.isBrand, isBrand) || other.isBrand == isBrand));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,text,isCategory,isBrand);

@override
String toString() {
  return 'SearchSuggestion(text: $text, isCategory: $isCategory, isBrand: $isBrand)';
}


}

/// @nodoc
abstract mixin class $SearchSuggestionCopyWith<$Res>  {
  factory $SearchSuggestionCopyWith(SearchSuggestion value, $Res Function(SearchSuggestion) _then) = _$SearchSuggestionCopyWithImpl;
@useResult
$Res call({
 String text, bool isCategory, bool isBrand
});




}
/// @nodoc
class _$SearchSuggestionCopyWithImpl<$Res>
    implements $SearchSuggestionCopyWith<$Res> {
  _$SearchSuggestionCopyWithImpl(this._self, this._then);

  final SearchSuggestion _self;
  final $Res Function(SearchSuggestion) _then;

/// Create a copy of SearchSuggestion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? text = null,Object? isCategory = null,Object? isBrand = null,}) {
  return _then(SearchSuggestion(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,isCategory: null == isCategory ? _self.isCategory : isCategory // ignore: cast_nullable_to_non_nullable
as bool,isBrand: null == isBrand ? _self.isBrand : isBrand // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [SearchSuggestion].
extension SearchSuggestionPatterns on SearchSuggestion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SearchSuggestion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SearchSuggestion() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SearchSuggestion value)  $default,){
final _that = this;
switch (_that) {
case _SearchSuggestion():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SearchSuggestion value)?  $default,){
final _that = this;
switch (_that) {
case _SearchSuggestion() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String text,  bool isCategory,  bool isBrand)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SearchSuggestion() when $default != null:
return $default(_that.text,_that.isCategory,_that.isBrand);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String text,  bool isCategory,  bool isBrand)  $default,) {final _that = this;
switch (_that) {
case _SearchSuggestion():
return $default(_that.text,_that.isCategory,_that.isBrand);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String text,  bool isCategory,  bool isBrand)?  $default,) {final _that = this;
switch (_that) {
case _SearchSuggestion() when $default != null:
return $default(_that.text,_that.isCategory,_that.isBrand);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SearchSuggestion implements SearchSuggestion {
  const _SearchSuggestion({required this.text, this.isCategory = false, this.isBrand = false});
  factory _SearchSuggestion.fromJson(Map<String, dynamic> json) => _$SearchSuggestionFromJson(json);

@override final  String text;
@override@JsonKey() final  bool isCategory;
@override@JsonKey() final  bool isBrand;

/// Create a copy of SearchSuggestion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SearchSuggestionCopyWith<_SearchSuggestion> get copyWith => __$SearchSuggestionCopyWithImpl<_SearchSuggestion>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SearchSuggestionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SearchSuggestion&&(identical(other.text, text) || other.text == text)&&(identical(other.isCategory, isCategory) || other.isCategory == isCategory)&&(identical(other.isBrand, isBrand) || other.isBrand == isBrand));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,text,isCategory,isBrand);

@override
String toString() {
  return 'SearchSuggestion(text: $text, isCategory: $isCategory, isBrand: $isBrand)';
}


}

/// @nodoc
abstract mixin class _$SearchSuggestionCopyWith<$Res> implements $SearchSuggestionCopyWith<$Res> {
  factory _$SearchSuggestionCopyWith(_SearchSuggestion value, $Res Function(_SearchSuggestion) _then) = __$SearchSuggestionCopyWithImpl;
@override @useResult
$Res call({
 String text, bool isCategory, bool isBrand
});




}
/// @nodoc
class __$SearchSuggestionCopyWithImpl<$Res>
    implements _$SearchSuggestionCopyWith<$Res> {
  __$SearchSuggestionCopyWithImpl(this._self, this._then);

  final _SearchSuggestion _self;
  final $Res Function(_SearchSuggestion) _then;

/// Create a copy of SearchSuggestion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? text = null,Object? isCategory = null,Object? isBrand = null,}) {
  return _then(_SearchSuggestion(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,isCategory: null == isCategory ? _self.isCategory : isCategory // ignore: cast_nullable_to_non_nullable
as bool,isBrand: null == isBrand ? _self.isBrand : isBrand // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$ShopProductResult {

 String get id; String get productId; String get productName; String get productImageUrl; String get shopId; String get shopName; double get price; bool get isAvailable; double get distanceInKm; double get shopRating; DateTime get lastUpdated; String? get variant; double? get mrp; String? get shopImageUrl; String? get offerText; String? get shopAddress; double? get shopLatitude; double? get shopLongitude; String? get category; String? get brand; int? get reviewCount;/// Whether the shop is currently open, per the backend's opening-hours
/// evaluation. Null means the backend did not report it (unknown), which
/// must never be rendered as "Open".
 bool? get isOpenNow;/// Whether the shop currently accepts orders. Null = unknown.
 bool? get isAcceptingOrders; InventoryAvailability get availability; FreshnessLevel get freshness;/// The backend's own freshness verdict verbatim (`RECENTLY_UPDATED` /
/// `STALE`), preserved so the UI can defer to the server's per-source
/// staleness threshold instead of re-guessing it client-side.
 String? get freshnessStatusRaw;
/// Create a copy of ShopProductResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShopProductResultCopyWith<ShopProductResult> get copyWith => _$ShopProductResultCopyWithImpl<ShopProductResult>(this as ShopProductResult, _$identity);

  /// Serializes this ShopProductResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShopProductResult&&(identical(other.id, id) || other.id == id)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.productName, productName) || other.productName == productName)&&(identical(other.productImageUrl, productImageUrl) || other.productImageUrl == productImageUrl)&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.shopName, shopName) || other.shopName == shopName)&&(identical(other.price, price) || other.price == price)&&(identical(other.isAvailable, isAvailable) || other.isAvailable == isAvailable)&&(identical(other.distanceInKm, distanceInKm) || other.distanceInKm == distanceInKm)&&(identical(other.shopRating, shopRating) || other.shopRating == shopRating)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated)&&(identical(other.variant, variant) || other.variant == variant)&&(identical(other.mrp, mrp) || other.mrp == mrp)&&(identical(other.shopImageUrl, shopImageUrl) || other.shopImageUrl == shopImageUrl)&&(identical(other.offerText, offerText) || other.offerText == offerText)&&(identical(other.shopAddress, shopAddress) || other.shopAddress == shopAddress)&&(identical(other.shopLatitude, shopLatitude) || other.shopLatitude == shopLatitude)&&(identical(other.shopLongitude, shopLongitude) || other.shopLongitude == shopLongitude)&&(identical(other.category, category) || other.category == category)&&(identical(other.brand, brand) || other.brand == brand)&&(identical(other.reviewCount, reviewCount) || other.reviewCount == reviewCount)&&(identical(other.isOpenNow, isOpenNow) || other.isOpenNow == isOpenNow)&&(identical(other.isAcceptingOrders, isAcceptingOrders) || other.isAcceptingOrders == isAcceptingOrders)&&(identical(other.availability, availability) || other.availability == availability)&&(identical(other.freshness, freshness) || other.freshness == freshness)&&(identical(other.freshnessStatusRaw, freshnessStatusRaw) || other.freshnessStatusRaw == freshnessStatusRaw));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,productId,productName,productImageUrl,shopId,shopName,price,isAvailable,distanceInKm,shopRating,lastUpdated,variant,mrp,shopImageUrl,offerText,shopAddress,shopLatitude,shopLongitude,category,brand,reviewCount,isOpenNow,isAcceptingOrders,availability,freshness,freshnessStatusRaw]);

@override
String toString() {
  return 'ShopProductResult(id: $id, productId: $productId, productName: $productName, productImageUrl: $productImageUrl, shopId: $shopId, shopName: $shopName, price: $price, isAvailable: $isAvailable, distanceInKm: $distanceInKm, shopRating: $shopRating, lastUpdated: $lastUpdated, variant: $variant, mrp: $mrp, shopImageUrl: $shopImageUrl, offerText: $offerText, shopAddress: $shopAddress, shopLatitude: $shopLatitude, shopLongitude: $shopLongitude, category: $category, brand: $brand, reviewCount: $reviewCount, isOpenNow: $isOpenNow, isAcceptingOrders: $isAcceptingOrders, availability: $availability, freshness: $freshness, freshnessStatusRaw: $freshnessStatusRaw)';
}


}

/// @nodoc
abstract mixin class $ShopProductResultCopyWith<$Res>  {
  factory $ShopProductResultCopyWith(ShopProductResult value, $Res Function(ShopProductResult) _then) = _$ShopProductResultCopyWithImpl;
@useResult
$Res call({
 String id, String productId, String productName, String productImageUrl, String shopId, String shopName, double price, bool isAvailable, double distanceInKm, double shopRating, DateTime lastUpdated, String? variant, double? mrp, String? shopImageUrl, String? offerText, String? shopAddress, double? shopLatitude, double? shopLongitude, String? category, String? brand, int? reviewCount, bool? isOpenNow, bool? isAcceptingOrders, InventoryAvailability availability, FreshnessLevel freshness, String? freshnessStatusRaw
});




}
/// @nodoc
class _$ShopProductResultCopyWithImpl<$Res>
    implements $ShopProductResultCopyWith<$Res> {
  _$ShopProductResultCopyWithImpl(this._self, this._then);

  final ShopProductResult _self;
  final $Res Function(ShopProductResult) _then;

/// Create a copy of ShopProductResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? productId = null,Object? productName = null,Object? productImageUrl = null,Object? shopId = null,Object? shopName = null,Object? price = null,Object? isAvailable = null,Object? distanceInKm = null,Object? shopRating = null,Object? lastUpdated = null,Object? variant = freezed,Object? mrp = freezed,Object? shopImageUrl = freezed,Object? offerText = freezed,Object? shopAddress = freezed,Object? shopLatitude = freezed,Object? shopLongitude = freezed,Object? category = freezed,Object? brand = freezed,Object? reviewCount = freezed,Object? isOpenNow = freezed,Object? isAcceptingOrders = freezed,Object? availability = null,Object? freshness = null,Object? freshnessStatusRaw = freezed,}) {
  return _then(ShopProductResult(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,productName: null == productName ? _self.productName : productName // ignore: cast_nullable_to_non_nullable
as String,productImageUrl: null == productImageUrl ? _self.productImageUrl : productImageUrl // ignore: cast_nullable_to_non_nullable
as String,shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,shopName: null == shopName ? _self.shopName : shopName // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,isAvailable: null == isAvailable ? _self.isAvailable : isAvailable // ignore: cast_nullable_to_non_nullable
as bool,distanceInKm: null == distanceInKm ? _self.distanceInKm : distanceInKm // ignore: cast_nullable_to_non_nullable
as double,shopRating: null == shopRating ? _self.shopRating : shopRating // ignore: cast_nullable_to_non_nullable
as double,lastUpdated: null == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as DateTime,variant: freezed == variant ? _self.variant : variant // ignore: cast_nullable_to_non_nullable
as String?,mrp: freezed == mrp ? _self.mrp : mrp // ignore: cast_nullable_to_non_nullable
as double?,shopImageUrl: freezed == shopImageUrl ? _self.shopImageUrl : shopImageUrl // ignore: cast_nullable_to_non_nullable
as String?,offerText: freezed == offerText ? _self.offerText : offerText // ignore: cast_nullable_to_non_nullable
as String?,shopAddress: freezed == shopAddress ? _self.shopAddress : shopAddress // ignore: cast_nullable_to_non_nullable
as String?,shopLatitude: freezed == shopLatitude ? _self.shopLatitude : shopLatitude // ignore: cast_nullable_to_non_nullable
as double?,shopLongitude: freezed == shopLongitude ? _self.shopLongitude : shopLongitude // ignore: cast_nullable_to_non_nullable
as double?,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,brand: freezed == brand ? _self.brand : brand // ignore: cast_nullable_to_non_nullable
as String?,reviewCount: freezed == reviewCount ? _self.reviewCount : reviewCount // ignore: cast_nullable_to_non_nullable
as int?,isOpenNow: freezed == isOpenNow ? _self.isOpenNow : isOpenNow // ignore: cast_nullable_to_non_nullable
as bool?,isAcceptingOrders: freezed == isAcceptingOrders ? _self.isAcceptingOrders : isAcceptingOrders // ignore: cast_nullable_to_non_nullable
as bool?,availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as InventoryAvailability,freshness: null == freshness ? _self.freshness : freshness // ignore: cast_nullable_to_non_nullable
as FreshnessLevel,freshnessStatusRaw: freezed == freshnessStatusRaw ? _self.freshnessStatusRaw : freshnessStatusRaw // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ShopProductResult].
extension ShopProductResultPatterns on ShopProductResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShopProductResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShopProductResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShopProductResult value)  $default,){
final _that = this;
switch (_that) {
case _ShopProductResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShopProductResult value)?  $default,){
final _that = this;
switch (_that) {
case _ShopProductResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String productId,  String productName,  String productImageUrl,  String shopId,  String shopName,  double price,  bool isAvailable,  double distanceInKm,  double shopRating,  DateTime lastUpdated,  String? variant,  double? mrp,  String? shopImageUrl,  String? offerText,  String? shopAddress,  double? shopLatitude,  double? shopLongitude,  String? category,  String? brand,  int? reviewCount,  bool? isOpenNow,  bool? isAcceptingOrders,  InventoryAvailability availability,  FreshnessLevel freshness,  String? freshnessStatusRaw)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShopProductResult() when $default != null:
return $default(_that.id,_that.productId,_that.productName,_that.productImageUrl,_that.shopId,_that.shopName,_that.price,_that.isAvailable,_that.distanceInKm,_that.shopRating,_that.lastUpdated,_that.variant,_that.mrp,_that.shopImageUrl,_that.offerText,_that.shopAddress,_that.shopLatitude,_that.shopLongitude,_that.category,_that.brand,_that.reviewCount,_that.isOpenNow,_that.isAcceptingOrders,_that.availability,_that.freshness,_that.freshnessStatusRaw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String productId,  String productName,  String productImageUrl,  String shopId,  String shopName,  double price,  bool isAvailable,  double distanceInKm,  double shopRating,  DateTime lastUpdated,  String? variant,  double? mrp,  String? shopImageUrl,  String? offerText,  String? shopAddress,  double? shopLatitude,  double? shopLongitude,  String? category,  String? brand,  int? reviewCount,  bool? isOpenNow,  bool? isAcceptingOrders,  InventoryAvailability availability,  FreshnessLevel freshness,  String? freshnessStatusRaw)  $default,) {final _that = this;
switch (_that) {
case _ShopProductResult():
return $default(_that.id,_that.productId,_that.productName,_that.productImageUrl,_that.shopId,_that.shopName,_that.price,_that.isAvailable,_that.distanceInKm,_that.shopRating,_that.lastUpdated,_that.variant,_that.mrp,_that.shopImageUrl,_that.offerText,_that.shopAddress,_that.shopLatitude,_that.shopLongitude,_that.category,_that.brand,_that.reviewCount,_that.isOpenNow,_that.isAcceptingOrders,_that.availability,_that.freshness,_that.freshnessStatusRaw);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String productId,  String productName,  String productImageUrl,  String shopId,  String shopName,  double price,  bool isAvailable,  double distanceInKm,  double shopRating,  DateTime lastUpdated,  String? variant,  double? mrp,  String? shopImageUrl,  String? offerText,  String? shopAddress,  double? shopLatitude,  double? shopLongitude,  String? category,  String? brand,  int? reviewCount,  bool? isOpenNow,  bool? isAcceptingOrders,  InventoryAvailability availability,  FreshnessLevel freshness,  String? freshnessStatusRaw)?  $default,) {final _that = this;
switch (_that) {
case _ShopProductResult() when $default != null:
return $default(_that.id,_that.productId,_that.productName,_that.productImageUrl,_that.shopId,_that.shopName,_that.price,_that.isAvailable,_that.distanceInKm,_that.shopRating,_that.lastUpdated,_that.variant,_that.mrp,_that.shopImageUrl,_that.offerText,_that.shopAddress,_that.shopLatitude,_that.shopLongitude,_that.category,_that.brand,_that.reviewCount,_that.isOpenNow,_that.isAcceptingOrders,_that.availability,_that.freshness,_that.freshnessStatusRaw);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ShopProductResult extends ShopProductResult {
  const _ShopProductResult({required this.id, required this.productId, required this.productName, required this.productImageUrl, required this.shopId, required this.shopName, required this.price, required this.isAvailable, required this.distanceInKm, required this.shopRating, required this.lastUpdated, this.variant, this.mrp, this.shopImageUrl, this.offerText, this.shopAddress, this.shopLatitude, this.shopLongitude, this.category, this.brand, this.reviewCount, this.isOpenNow, this.isAcceptingOrders, this.availability = InventoryAvailability.unknown, this.freshness = FreshnessLevel.unknown, this.freshnessStatusRaw}): super._();
  factory _ShopProductResult.fromJson(Map<String, dynamic> json) => _$ShopProductResultFromJson(json);

@override final  String id;
@override final  String productId;
@override final  String productName;
@override final  String productImageUrl;
@override final  String shopId;
@override final  String shopName;
@override final  double price;
@override final  bool isAvailable;
@override final  double distanceInKm;
@override final  double shopRating;
@override final  DateTime lastUpdated;
@override final  String? variant;
@override final  double? mrp;
@override final  String? shopImageUrl;
@override final  String? offerText;
@override final  String? shopAddress;
@override final  double? shopLatitude;
@override final  double? shopLongitude;
@override final  String? category;
@override final  String? brand;
@override final  int? reviewCount;
/// Whether the shop is currently open, per the backend's opening-hours
/// evaluation. Null means the backend did not report it (unknown), which
/// must never be rendered as "Open".
@override final  bool? isOpenNow;
/// Whether the shop currently accepts orders. Null = unknown.
@override final  bool? isAcceptingOrders;
@override@JsonKey() final  InventoryAvailability availability;
@override@JsonKey() final  FreshnessLevel freshness;
/// The backend's own freshness verdict verbatim (`RECENTLY_UPDATED` /
/// `STALE`), preserved so the UI can defer to the server's per-source
/// staleness threshold instead of re-guessing it client-side.
@override final  String? freshnessStatusRaw;

/// Create a copy of ShopProductResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShopProductResultCopyWith<_ShopProductResult> get copyWith => __$ShopProductResultCopyWithImpl<_ShopProductResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ShopProductResultToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShopProductResult&&(identical(other.id, id) || other.id == id)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.productName, productName) || other.productName == productName)&&(identical(other.productImageUrl, productImageUrl) || other.productImageUrl == productImageUrl)&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.shopName, shopName) || other.shopName == shopName)&&(identical(other.price, price) || other.price == price)&&(identical(other.isAvailable, isAvailable) || other.isAvailable == isAvailable)&&(identical(other.distanceInKm, distanceInKm) || other.distanceInKm == distanceInKm)&&(identical(other.shopRating, shopRating) || other.shopRating == shopRating)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated)&&(identical(other.variant, variant) || other.variant == variant)&&(identical(other.mrp, mrp) || other.mrp == mrp)&&(identical(other.shopImageUrl, shopImageUrl) || other.shopImageUrl == shopImageUrl)&&(identical(other.offerText, offerText) || other.offerText == offerText)&&(identical(other.shopAddress, shopAddress) || other.shopAddress == shopAddress)&&(identical(other.shopLatitude, shopLatitude) || other.shopLatitude == shopLatitude)&&(identical(other.shopLongitude, shopLongitude) || other.shopLongitude == shopLongitude)&&(identical(other.category, category) || other.category == category)&&(identical(other.brand, brand) || other.brand == brand)&&(identical(other.reviewCount, reviewCount) || other.reviewCount == reviewCount)&&(identical(other.isOpenNow, isOpenNow) || other.isOpenNow == isOpenNow)&&(identical(other.isAcceptingOrders, isAcceptingOrders) || other.isAcceptingOrders == isAcceptingOrders)&&(identical(other.availability, availability) || other.availability == availability)&&(identical(other.freshness, freshness) || other.freshness == freshness)&&(identical(other.freshnessStatusRaw, freshnessStatusRaw) || other.freshnessStatusRaw == freshnessStatusRaw));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,productId,productName,productImageUrl,shopId,shopName,price,isAvailable,distanceInKm,shopRating,lastUpdated,variant,mrp,shopImageUrl,offerText,shopAddress,shopLatitude,shopLongitude,category,brand,reviewCount,isOpenNow,isAcceptingOrders,availability,freshness,freshnessStatusRaw]);

@override
String toString() {
  return 'ShopProductResult(id: $id, productId: $productId, productName: $productName, productImageUrl: $productImageUrl, shopId: $shopId, shopName: $shopName, price: $price, isAvailable: $isAvailable, distanceInKm: $distanceInKm, shopRating: $shopRating, lastUpdated: $lastUpdated, variant: $variant, mrp: $mrp, shopImageUrl: $shopImageUrl, offerText: $offerText, shopAddress: $shopAddress, shopLatitude: $shopLatitude, shopLongitude: $shopLongitude, category: $category, brand: $brand, reviewCount: $reviewCount, isOpenNow: $isOpenNow, isAcceptingOrders: $isAcceptingOrders, availability: $availability, freshness: $freshness, freshnessStatusRaw: $freshnessStatusRaw)';
}


}

/// @nodoc
abstract mixin class _$ShopProductResultCopyWith<$Res> implements $ShopProductResultCopyWith<$Res> {
  factory _$ShopProductResultCopyWith(_ShopProductResult value, $Res Function(_ShopProductResult) _then) = __$ShopProductResultCopyWithImpl;
@override @useResult
$Res call({
 String id, String productId, String productName, String productImageUrl, String shopId, String shopName, double price, bool isAvailable, double distanceInKm, double shopRating, DateTime lastUpdated, String? variant, double? mrp, String? shopImageUrl, String? offerText, String? shopAddress, double? shopLatitude, double? shopLongitude, String? category, String? brand, int? reviewCount, bool? isOpenNow, bool? isAcceptingOrders, InventoryAvailability availability, FreshnessLevel freshness, String? freshnessStatusRaw
});




}
/// @nodoc
class __$ShopProductResultCopyWithImpl<$Res>
    implements _$ShopProductResultCopyWith<$Res> {
  __$ShopProductResultCopyWithImpl(this._self, this._then);

  final _ShopProductResult _self;
  final $Res Function(_ShopProductResult) _then;

/// Create a copy of ShopProductResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? productId = null,Object? productName = null,Object? productImageUrl = null,Object? shopId = null,Object? shopName = null,Object? price = null,Object? isAvailable = null,Object? distanceInKm = null,Object? shopRating = null,Object? lastUpdated = null,Object? variant = freezed,Object? mrp = freezed,Object? shopImageUrl = freezed,Object? offerText = freezed,Object? shopAddress = freezed,Object? shopLatitude = freezed,Object? shopLongitude = freezed,Object? category = freezed,Object? brand = freezed,Object? reviewCount = freezed,Object? isOpenNow = freezed,Object? isAcceptingOrders = freezed,Object? availability = null,Object? freshness = null,Object? freshnessStatusRaw = freezed,}) {
  return _then(_ShopProductResult(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,productName: null == productName ? _self.productName : productName // ignore: cast_nullable_to_non_nullable
as String,productImageUrl: null == productImageUrl ? _self.productImageUrl : productImageUrl // ignore: cast_nullable_to_non_nullable
as String,shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,shopName: null == shopName ? _self.shopName : shopName // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,isAvailable: null == isAvailable ? _self.isAvailable : isAvailable // ignore: cast_nullable_to_non_nullable
as bool,distanceInKm: null == distanceInKm ? _self.distanceInKm : distanceInKm // ignore: cast_nullable_to_non_nullable
as double,shopRating: null == shopRating ? _self.shopRating : shopRating // ignore: cast_nullable_to_non_nullable
as double,lastUpdated: null == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as DateTime,variant: freezed == variant ? _self.variant : variant // ignore: cast_nullable_to_non_nullable
as String?,mrp: freezed == mrp ? _self.mrp : mrp // ignore: cast_nullable_to_non_nullable
as double?,shopImageUrl: freezed == shopImageUrl ? _self.shopImageUrl : shopImageUrl // ignore: cast_nullable_to_non_nullable
as String?,offerText: freezed == offerText ? _self.offerText : offerText // ignore: cast_nullable_to_non_nullable
as String?,shopAddress: freezed == shopAddress ? _self.shopAddress : shopAddress // ignore: cast_nullable_to_non_nullable
as String?,shopLatitude: freezed == shopLatitude ? _self.shopLatitude : shopLatitude // ignore: cast_nullable_to_non_nullable
as double?,shopLongitude: freezed == shopLongitude ? _self.shopLongitude : shopLongitude // ignore: cast_nullable_to_non_nullable
as double?,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,brand: freezed == brand ? _self.brand : brand // ignore: cast_nullable_to_non_nullable
as String?,reviewCount: freezed == reviewCount ? _self.reviewCount : reviewCount // ignore: cast_nullable_to_non_nullable
as int?,isOpenNow: freezed == isOpenNow ? _self.isOpenNow : isOpenNow // ignore: cast_nullable_to_non_nullable
as bool?,isAcceptingOrders: freezed == isAcceptingOrders ? _self.isAcceptingOrders : isAcceptingOrders // ignore: cast_nullable_to_non_nullable
as bool?,availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as InventoryAvailability,freshness: null == freshness ? _self.freshness : freshness // ignore: cast_nullable_to_non_nullable
as FreshnessLevel,freshnessStatusRaw: freezed == freshnessStatusRaw ? _self.freshnessStatusRaw : freshnessStatusRaw // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
