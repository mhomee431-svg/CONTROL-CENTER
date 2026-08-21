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

 String get id; String get productId; String get productName; String get productImageUrl; String get shopId; String get shopName; double get price; bool get isAvailable; double get distanceInKm; double get shopRating; DateTime get lastUpdated; String? get offerText;
/// Create a copy of ShopProductResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShopProductResultCopyWith<ShopProductResult> get copyWith => _$ShopProductResultCopyWithImpl<ShopProductResult>(this as ShopProductResult, _$identity);

  /// Serializes this ShopProductResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShopProductResult&&(identical(other.id, id) || other.id == id)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.productName, productName) || other.productName == productName)&&(identical(other.productImageUrl, productImageUrl) || other.productImageUrl == productImageUrl)&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.shopName, shopName) || other.shopName == shopName)&&(identical(other.price, price) || other.price == price)&&(identical(other.isAvailable, isAvailable) || other.isAvailable == isAvailable)&&(identical(other.distanceInKm, distanceInKm) || other.distanceInKm == distanceInKm)&&(identical(other.shopRating, shopRating) || other.shopRating == shopRating)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated)&&(identical(other.offerText, offerText) || other.offerText == offerText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,productId,productName,productImageUrl,shopId,shopName,price,isAvailable,distanceInKm,shopRating,lastUpdated,offerText);

@override
String toString() {
  return 'ShopProductResult(id: $id, productId: $productId, productName: $productName, productImageUrl: $productImageUrl, shopId: $shopId, shopName: $shopName, price: $price, isAvailable: $isAvailable, distanceInKm: $distanceInKm, shopRating: $shopRating, lastUpdated: $lastUpdated, offerText: $offerText)';
}


}

/// @nodoc
abstract mixin class $ShopProductResultCopyWith<$Res>  {
  factory $ShopProductResultCopyWith(ShopProductResult value, $Res Function(ShopProductResult) _then) = _$ShopProductResultCopyWithImpl;
@useResult
$Res call({
 String id, String productId, String productName, String productImageUrl, String shopId, String shopName, double price, bool isAvailable, double distanceInKm, double shopRating, DateTime lastUpdated, String? offerText
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? productId = null,Object? productName = null,Object? productImageUrl = null,Object? shopId = null,Object? shopName = null,Object? price = null,Object? isAvailable = null,Object? distanceInKm = null,Object? shopRating = null,Object? lastUpdated = null,Object? offerText = freezed,}) {
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
as DateTime,offerText: freezed == offerText ? _self.offerText : offerText // ignore: cast_nullable_to_non_nullable
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String productId,  String productName,  String productImageUrl,  String shopId,  String shopName,  double price,  bool isAvailable,  double distanceInKm,  double shopRating,  DateTime lastUpdated,  String? offerText)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShopProductResult() when $default != null:
return $default(_that.id,_that.productId,_that.productName,_that.productImageUrl,_that.shopId,_that.shopName,_that.price,_that.isAvailable,_that.distanceInKm,_that.shopRating,_that.lastUpdated,_that.offerText);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String productId,  String productName,  String productImageUrl,  String shopId,  String shopName,  double price,  bool isAvailable,  double distanceInKm,  double shopRating,  DateTime lastUpdated,  String? offerText)  $default,) {final _that = this;
switch (_that) {
case _ShopProductResult():
return $default(_that.id,_that.productId,_that.productName,_that.productImageUrl,_that.shopId,_that.shopName,_that.price,_that.isAvailable,_that.distanceInKm,_that.shopRating,_that.lastUpdated,_that.offerText);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String productId,  String productName,  String productImageUrl,  String shopId,  String shopName,  double price,  bool isAvailable,  double distanceInKm,  double shopRating,  DateTime lastUpdated,  String? offerText)?  $default,) {final _that = this;
switch (_that) {
case _ShopProductResult() when $default != null:
return $default(_that.id,_that.productId,_that.productName,_that.productImageUrl,_that.shopId,_that.shopName,_that.price,_that.isAvailable,_that.distanceInKm,_that.shopRating,_that.lastUpdated,_that.offerText);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ShopProductResult implements ShopProductResult {
  const _ShopProductResult({required this.id, required this.productId, required this.productName, required this.productImageUrl, required this.shopId, required this.shopName, required this.price, required this.isAvailable, required this.distanceInKm, required this.shopRating, required this.lastUpdated, this.offerText});
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
@override final  String? offerText;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShopProductResult&&(identical(other.id, id) || other.id == id)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.productName, productName) || other.productName == productName)&&(identical(other.productImageUrl, productImageUrl) || other.productImageUrl == productImageUrl)&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.shopName, shopName) || other.shopName == shopName)&&(identical(other.price, price) || other.price == price)&&(identical(other.isAvailable, isAvailable) || other.isAvailable == isAvailable)&&(identical(other.distanceInKm, distanceInKm) || other.distanceInKm == distanceInKm)&&(identical(other.shopRating, shopRating) || other.shopRating == shopRating)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated)&&(identical(other.offerText, offerText) || other.offerText == offerText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,productId,productName,productImageUrl,shopId,shopName,price,isAvailable,distanceInKm,shopRating,lastUpdated,offerText);

@override
String toString() {
  return 'ShopProductResult(id: $id, productId: $productId, productName: $productName, productImageUrl: $productImageUrl, shopId: $shopId, shopName: $shopName, price: $price, isAvailable: $isAvailable, distanceInKm: $distanceInKm, shopRating: $shopRating, lastUpdated: $lastUpdated, offerText: $offerText)';
}


}

/// @nodoc
abstract mixin class _$ShopProductResultCopyWith<$Res> implements $ShopProductResultCopyWith<$Res> {
  factory _$ShopProductResultCopyWith(_ShopProductResult value, $Res Function(_ShopProductResult) _then) = __$ShopProductResultCopyWithImpl;
@override @useResult
$Res call({
 String id, String productId, String productName, String productImageUrl, String shopId, String shopName, double price, bool isAvailable, double distanceInKm, double shopRating, DateTime lastUpdated, String? offerText
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? productId = null,Object? productName = null,Object? productImageUrl = null,Object? shopId = null,Object? shopName = null,Object? price = null,Object? isAvailable = null,Object? distanceInKm = null,Object? shopRating = null,Object? lastUpdated = null,Object? offerText = freezed,}) {
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
as DateTime,offerText: freezed == offerText ? _self.offerText : offerText // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
