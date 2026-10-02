// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'shop_details_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ShopProductSummary {

 String get productId; String get name; String get imageUrl; double get price; bool get isAvailable;
/// Create a copy of ShopProductSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShopProductSummaryCopyWith<ShopProductSummary> get copyWith => _$ShopProductSummaryCopyWithImpl<ShopProductSummary>(this as ShopProductSummary, _$identity);

  /// Serializes this ShopProductSummary to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShopProductSummary&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.name, name) || other.name == name)&&(identical(other.imageUrl, imageUrl) || other.imageUrl == imageUrl)&&(identical(other.price, price) || other.price == price)&&(identical(other.isAvailable, isAvailable) || other.isAvailable == isAvailable));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,productId,name,imageUrl,price,isAvailable);

@override
String toString() {
  return 'ShopProductSummary(productId: $productId, name: $name, imageUrl: $imageUrl, price: $price, isAvailable: $isAvailable)';
}


}

/// @nodoc
abstract mixin class $ShopProductSummaryCopyWith<$Res>  {
  factory $ShopProductSummaryCopyWith(ShopProductSummary value, $Res Function(ShopProductSummary) _then) = _$ShopProductSummaryCopyWithImpl;
@useResult
$Res call({
 String productId, String name, String imageUrl, double price, bool isAvailable
});




}
/// @nodoc
class _$ShopProductSummaryCopyWithImpl<$Res>
    implements $ShopProductSummaryCopyWith<$Res> {
  _$ShopProductSummaryCopyWithImpl(this._self, this._then);

  final ShopProductSummary _self;
  final $Res Function(ShopProductSummary) _then;

/// Create a copy of ShopProductSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? productId = null,Object? name = null,Object? imageUrl = null,Object? price = null,Object? isAvailable = null,}) {
  return _then(ShopProductSummary(
productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,imageUrl: null == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,isAvailable: null == isAvailable ? _self.isAvailable : isAvailable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ShopProductSummary].
extension ShopProductSummaryPatterns on ShopProductSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShopProductSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShopProductSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShopProductSummary value)  $default,){
final _that = this;
switch (_that) {
case _ShopProductSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShopProductSummary value)?  $default,){
final _that = this;
switch (_that) {
case _ShopProductSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String productId,  String name,  String imageUrl,  double price,  bool isAvailable)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShopProductSummary() when $default != null:
return $default(_that.productId,_that.name,_that.imageUrl,_that.price,_that.isAvailable);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String productId,  String name,  String imageUrl,  double price,  bool isAvailable)  $default,) {final _that = this;
switch (_that) {
case _ShopProductSummary():
return $default(_that.productId,_that.name,_that.imageUrl,_that.price,_that.isAvailable);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String productId,  String name,  String imageUrl,  double price,  bool isAvailable)?  $default,) {final _that = this;
switch (_that) {
case _ShopProductSummary() when $default != null:
return $default(_that.productId,_that.name,_that.imageUrl,_that.price,_that.isAvailable);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ShopProductSummary implements ShopProductSummary {
  const _ShopProductSummary({required this.productId, required this.name, required this.imageUrl, required this.price, required this.isAvailable});
  factory _ShopProductSummary.fromJson(Map<String, dynamic> json) => _$ShopProductSummaryFromJson(json);

@override final  String productId;
@override final  String name;
@override final  String imageUrl;
@override final  double price;
@override final  bool isAvailable;

/// Create a copy of ShopProductSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShopProductSummaryCopyWith<_ShopProductSummary> get copyWith => __$ShopProductSummaryCopyWithImpl<_ShopProductSummary>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ShopProductSummaryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShopProductSummary&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.name, name) || other.name == name)&&(identical(other.imageUrl, imageUrl) || other.imageUrl == imageUrl)&&(identical(other.price, price) || other.price == price)&&(identical(other.isAvailable, isAvailable) || other.isAvailable == isAvailable));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,productId,name,imageUrl,price,isAvailable);

@override
String toString() {
  return 'ShopProductSummary(productId: $productId, name: $name, imageUrl: $imageUrl, price: $price, isAvailable: $isAvailable)';
}


}

/// @nodoc
abstract mixin class _$ShopProductSummaryCopyWith<$Res> implements $ShopProductSummaryCopyWith<$Res> {
  factory _$ShopProductSummaryCopyWith(_ShopProductSummary value, $Res Function(_ShopProductSummary) _then) = __$ShopProductSummaryCopyWithImpl;
@override @useResult
$Res call({
 String productId, String name, String imageUrl, double price, bool isAvailable
});




}
/// @nodoc
class __$ShopProductSummaryCopyWithImpl<$Res>
    implements _$ShopProductSummaryCopyWith<$Res> {
  __$ShopProductSummaryCopyWithImpl(this._self, this._then);

  final _ShopProductSummary _self;
  final $Res Function(_ShopProductSummary) _then;

/// Create a copy of ShopProductSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? productId = null,Object? name = null,Object? imageUrl = null,Object? price = null,Object? isAvailable = null,}) {
  return _then(_ShopProductSummary(
productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,imageUrl: null == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,isAvailable: null == isAvailable ? _self.isAvailable : isAvailable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$ShopProfile {

 String get id; String get name; String get imageUrl; double get rating; int get reviewCount; String get address; double get distanceInKm; String get openingHours; bool get isOpenNow; String get phone; String get about; DateTime get lastInventoryUpdate; List<String> get activeOffers; List<ShopProductSummary> get availableProducts; bool get isSaved;/// Categories the shop belongs to (e.g. "Electronics", "Mobile").
 List<String> get categories;/// What this business may show a customer, as backend wire names
/// (see `BusinessCapability`). Shipped on the shop payload so a restaurant
/// or a service provider never inherits product-style price/stock UI —
/// and so a category or a capability added later reaches customers without
/// an app release.
///
/// May be EMPTY when the payload predates capabilities (older backend, or
/// served from the offline cache): [effectiveCapabilities] then resolves the
/// compiled fallback instead of leaving the profile surface-less.
 List<String> get capabilities;/// Canonical merchant-category NAME from the backend (e.g. "Restaurants",
/// "Transport", "Personal Transport / Personal Travel"), or '' when absent.
/// One input to the compiled fallback in [effectiveCapabilities].
 String get businessCategoryName;/// Canonical merchant-category CODE from the backend (e.g. "RESTAURANTS"),
/// or '' when absent.
 String get businessCategoryCode;/// Free-form business type ("Retail", "Service", ...), or '' when absent.
/// A "Service" type is the only signal a service business without a
/// recognised category can give.
 String get businessType;/// Whether the shop is verified by the platform.
 bool get isVerified;/// Shop latitude coordinate (0 = unavailable).
 double get latitude;/// Shop longitude coordinate (0 = unavailable).
 double get longitude;/// Secondary contact (e.g. WhatsApp) if available.
 String get secondaryPhone;/// Email contact if available.
 String get email;
/// Create a copy of ShopProfile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShopProfileCopyWith<ShopProfile> get copyWith => _$ShopProfileCopyWithImpl<ShopProfile>(this as ShopProfile, _$identity);

  /// Serializes this ShopProfile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShopProfile&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.imageUrl, imageUrl) || other.imageUrl == imageUrl)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.reviewCount, reviewCount) || other.reviewCount == reviewCount)&&(identical(other.address, address) || other.address == address)&&(identical(other.distanceInKm, distanceInKm) || other.distanceInKm == distanceInKm)&&(identical(other.openingHours, openingHours) || other.openingHours == openingHours)&&(identical(other.isOpenNow, isOpenNow) || other.isOpenNow == isOpenNow)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.about, about) || other.about == about)&&(identical(other.lastInventoryUpdate, lastInventoryUpdate) || other.lastInventoryUpdate == lastInventoryUpdate)&&const DeepCollectionEquality().equals(other.activeOffers, activeOffers)&&const DeepCollectionEquality().equals(other.availableProducts, availableProducts)&&(identical(other.isSaved, isSaved) || other.isSaved == isSaved)&&const DeepCollectionEquality().equals(other.categories, categories)&&const DeepCollectionEquality().equals(other.capabilities, capabilities)&&(identical(other.businessCategoryName, businessCategoryName) || other.businessCategoryName == businessCategoryName)&&(identical(other.businessCategoryCode, businessCategoryCode) || other.businessCategoryCode == businessCategoryCode)&&(identical(other.businessType, businessType) || other.businessType == businessType)&&(identical(other.isVerified, isVerified) || other.isVerified == isVerified)&&(identical(other.latitude, latitude) || other.latitude == latitude)&&(identical(other.longitude, longitude) || other.longitude == longitude)&&(identical(other.secondaryPhone, secondaryPhone) || other.secondaryPhone == secondaryPhone)&&(identical(other.email, email) || other.email == email));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,name,imageUrl,rating,reviewCount,address,distanceInKm,openingHours,isOpenNow,phone,about,lastInventoryUpdate,const DeepCollectionEquality().hash(activeOffers),const DeepCollectionEquality().hash(availableProducts),isSaved,const DeepCollectionEquality().hash(categories),const DeepCollectionEquality().hash(capabilities),businessCategoryName,businessCategoryCode,businessType,isVerified,latitude,longitude,secondaryPhone,email]);

@override
String toString() {
  return 'ShopProfile(id: $id, name: $name, imageUrl: $imageUrl, rating: $rating, reviewCount: $reviewCount, address: $address, distanceInKm: $distanceInKm, openingHours: $openingHours, isOpenNow: $isOpenNow, phone: $phone, about: $about, lastInventoryUpdate: $lastInventoryUpdate, activeOffers: $activeOffers, availableProducts: $availableProducts, isSaved: $isSaved, categories: $categories, capabilities: $capabilities, businessCategoryName: $businessCategoryName, businessCategoryCode: $businessCategoryCode, businessType: $businessType, isVerified: $isVerified, latitude: $latitude, longitude: $longitude, secondaryPhone: $secondaryPhone, email: $email)';
}


}

/// @nodoc
abstract mixin class $ShopProfileCopyWith<$Res>  {
  factory $ShopProfileCopyWith(ShopProfile value, $Res Function(ShopProfile) _then) = _$ShopProfileCopyWithImpl;
@useResult
$Res call({
 String id, String name, String imageUrl, double rating, int reviewCount, String address, double distanceInKm, String openingHours, bool isOpenNow, String phone, String about, DateTime lastInventoryUpdate, List<String> activeOffers, List<ShopProductSummary> availableProducts, bool isSaved, List<String> categories, List<String> capabilities, String businessCategoryName, String businessCategoryCode, String businessType, bool isVerified, double latitude, double longitude, String secondaryPhone, String email
});




}
/// @nodoc
class _$ShopProfileCopyWithImpl<$Res>
    implements $ShopProfileCopyWith<$Res> {
  _$ShopProfileCopyWithImpl(this._self, this._then);

  final ShopProfile _self;
  final $Res Function(ShopProfile) _then;

/// Create a copy of ShopProfile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? imageUrl = null,Object? rating = null,Object? reviewCount = null,Object? address = null,Object? distanceInKm = null,Object? openingHours = null,Object? isOpenNow = null,Object? phone = null,Object? about = null,Object? lastInventoryUpdate = null,Object? activeOffers = null,Object? availableProducts = null,Object? isSaved = null,Object? categories = null,Object? capabilities = null,Object? businessCategoryName = null,Object? businessCategoryCode = null,Object? businessType = null,Object? isVerified = null,Object? latitude = null,Object? longitude = null,Object? secondaryPhone = null,Object? email = null,}) {
  return _then(ShopProfile(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,imageUrl: null == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double,reviewCount: null == reviewCount ? _self.reviewCount : reviewCount // ignore: cast_nullable_to_non_nullable
as int,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,distanceInKm: null == distanceInKm ? _self.distanceInKm : distanceInKm // ignore: cast_nullable_to_non_nullable
as double,openingHours: null == openingHours ? _self.openingHours : openingHours // ignore: cast_nullable_to_non_nullable
as String,isOpenNow: null == isOpenNow ? _self.isOpenNow : isOpenNow // ignore: cast_nullable_to_non_nullable
as bool,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,about: null == about ? _self.about : about // ignore: cast_nullable_to_non_nullable
as String,lastInventoryUpdate: null == lastInventoryUpdate ? _self.lastInventoryUpdate : lastInventoryUpdate // ignore: cast_nullable_to_non_nullable
as DateTime,activeOffers: null == activeOffers ? _self.activeOffers : activeOffers // ignore: cast_nullable_to_non_nullable
as List<String>,availableProducts: null == availableProducts ? _self.availableProducts : availableProducts // ignore: cast_nullable_to_non_nullable
as List<ShopProductSummary>,isSaved: null == isSaved ? _self.isSaved : isSaved // ignore: cast_nullable_to_non_nullable
as bool,categories: null == categories ? _self.categories : categories // ignore: cast_nullable_to_non_nullable
as List<String>,capabilities: null == capabilities ? _self.capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as List<String>,businessCategoryName: null == businessCategoryName ? _self.businessCategoryName : businessCategoryName // ignore: cast_nullable_to_non_nullable
as String,businessCategoryCode: null == businessCategoryCode ? _self.businessCategoryCode : businessCategoryCode // ignore: cast_nullable_to_non_nullable
as String,businessType: null == businessType ? _self.businessType : businessType // ignore: cast_nullable_to_non_nullable
as String,isVerified: null == isVerified ? _self.isVerified : isVerified // ignore: cast_nullable_to_non_nullable
as bool,latitude: null == latitude ? _self.latitude : latitude // ignore: cast_nullable_to_non_nullable
as double,longitude: null == longitude ? _self.longitude : longitude // ignore: cast_nullable_to_non_nullable
as double,secondaryPhone: null == secondaryPhone ? _self.secondaryPhone : secondaryPhone // ignore: cast_nullable_to_non_nullable
as String,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ShopProfile].
extension ShopProfilePatterns on ShopProfile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShopProfile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShopProfile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShopProfile value)  $default,){
final _that = this;
switch (_that) {
case _ShopProfile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShopProfile value)?  $default,){
final _that = this;
switch (_that) {
case _ShopProfile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String imageUrl,  double rating,  int reviewCount,  String address,  double distanceInKm,  String openingHours,  bool isOpenNow,  String phone,  String about,  DateTime lastInventoryUpdate,  List<String> activeOffers,  List<ShopProductSummary> availableProducts,  bool isSaved,  List<String> categories,  List<String> capabilities,  String businessCategoryName,  String businessCategoryCode,  String businessType,  bool isVerified,  double latitude,  double longitude,  String secondaryPhone,  String email)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShopProfile() when $default != null:
return $default(_that.id,_that.name,_that.imageUrl,_that.rating,_that.reviewCount,_that.address,_that.distanceInKm,_that.openingHours,_that.isOpenNow,_that.phone,_that.about,_that.lastInventoryUpdate,_that.activeOffers,_that.availableProducts,_that.isSaved,_that.categories,_that.capabilities,_that.businessCategoryName,_that.businessCategoryCode,_that.businessType,_that.isVerified,_that.latitude,_that.longitude,_that.secondaryPhone,_that.email);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String imageUrl,  double rating,  int reviewCount,  String address,  double distanceInKm,  String openingHours,  bool isOpenNow,  String phone,  String about,  DateTime lastInventoryUpdate,  List<String> activeOffers,  List<ShopProductSummary> availableProducts,  bool isSaved,  List<String> categories,  List<String> capabilities,  String businessCategoryName,  String businessCategoryCode,  String businessType,  bool isVerified,  double latitude,  double longitude,  String secondaryPhone,  String email)  $default,) {final _that = this;
switch (_that) {
case _ShopProfile():
return $default(_that.id,_that.name,_that.imageUrl,_that.rating,_that.reviewCount,_that.address,_that.distanceInKm,_that.openingHours,_that.isOpenNow,_that.phone,_that.about,_that.lastInventoryUpdate,_that.activeOffers,_that.availableProducts,_that.isSaved,_that.categories,_that.capabilities,_that.businessCategoryName,_that.businessCategoryCode,_that.businessType,_that.isVerified,_that.latitude,_that.longitude,_that.secondaryPhone,_that.email);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String imageUrl,  double rating,  int reviewCount,  String address,  double distanceInKm,  String openingHours,  bool isOpenNow,  String phone,  String about,  DateTime lastInventoryUpdate,  List<String> activeOffers,  List<ShopProductSummary> availableProducts,  bool isSaved,  List<String> categories,  List<String> capabilities,  String businessCategoryName,  String businessCategoryCode,  String businessType,  bool isVerified,  double latitude,  double longitude,  String secondaryPhone,  String email)?  $default,) {final _that = this;
switch (_that) {
case _ShopProfile() when $default != null:
return $default(_that.id,_that.name,_that.imageUrl,_that.rating,_that.reviewCount,_that.address,_that.distanceInKm,_that.openingHours,_that.isOpenNow,_that.phone,_that.about,_that.lastInventoryUpdate,_that.activeOffers,_that.availableProducts,_that.isSaved,_that.categories,_that.capabilities,_that.businessCategoryName,_that.businessCategoryCode,_that.businessType,_that.isVerified,_that.latitude,_that.longitude,_that.secondaryPhone,_that.email);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ShopProfile extends ShopProfile {
  const _ShopProfile({required this.id, required this.name, required this.imageUrl, required this.rating, required this.reviewCount, required this.address, required this.distanceInKm, required this.openingHours, required this.isOpenNow, required this.phone, required this.about, required this.lastInventoryUpdate, required  List<String> activeOffers, required  List<ShopProductSummary> availableProducts, this.isSaved = false,  List<String> categories = const [],  List<String> capabilities = const [], this.businessCategoryName = '', this.businessCategoryCode = '', this.businessType = '', this.isVerified = false, this.latitude = 0.0, this.longitude = 0.0, this.secondaryPhone = '', this.email = ''}): _activeOffers = activeOffers,_availableProducts = availableProducts,_categories = categories,_capabilities = capabilities,super._();
  factory _ShopProfile.fromJson(Map<String, dynamic> json) => _$ShopProfileFromJson(json);

@override final  String id;
@override final  String name;
@override final  String imageUrl;
@override final  double rating;
@override final  int reviewCount;
@override final  String address;
@override final  double distanceInKm;
@override final  String openingHours;
@override final  bool isOpenNow;
@override final  String phone;
@override final  String about;
@override final  DateTime lastInventoryUpdate;
 final  List<String> _activeOffers;
@override List<String> get activeOffers {
  if (_activeOffers is EqualUnmodifiableListView) return _activeOffers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_activeOffers);
}

 final  List<ShopProductSummary> _availableProducts;
@override List<ShopProductSummary> get availableProducts {
  if (_availableProducts is EqualUnmodifiableListView) return _availableProducts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_availableProducts);
}

@override@JsonKey() final  bool isSaved;
/// Categories the shop belongs to (e.g. "Electronics", "Mobile").
 final  List<String> _categories;
/// Categories the shop belongs to (e.g. "Electronics", "Mobile").
@override@JsonKey() List<String> get categories {
  if (_categories is EqualUnmodifiableListView) return _categories;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_categories);
}

/// What this business may show a customer, as backend wire names
/// (see `BusinessCapability`). Shipped on the shop payload so a restaurant
/// or a service provider never inherits product-style price/stock UI —
/// and so a category or a capability added later reaches customers without
/// an app release.
///
/// May be EMPTY when the payload predates capabilities (older backend, or
/// served from the offline cache): [effectiveCapabilities] then resolves the
/// compiled fallback instead of leaving the profile surface-less.
 final  List<String> _capabilities;
/// What this business may show a customer, as backend wire names
/// (see `BusinessCapability`). Shipped on the shop payload so a restaurant
/// or a service provider never inherits product-style price/stock UI —
/// and so a category or a capability added later reaches customers without
/// an app release.
///
/// May be EMPTY when the payload predates capabilities (older backend, or
/// served from the offline cache): [effectiveCapabilities] then resolves the
/// compiled fallback instead of leaving the profile surface-less.
@override@JsonKey() List<String> get capabilities {
  if (_capabilities is EqualUnmodifiableListView) return _capabilities;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_capabilities);
}

/// Canonical merchant-category NAME from the backend (e.g. "Restaurants",
/// "Transport", "Personal Transport / Personal Travel"), or '' when absent.
/// One input to the compiled fallback in [effectiveCapabilities].
@override@JsonKey() final  String businessCategoryName;
/// Canonical merchant-category CODE from the backend (e.g. "RESTAURANTS"),
/// or '' when absent.
@override@JsonKey() final  String businessCategoryCode;
/// Free-form business type ("Retail", "Service", ...), or '' when absent.
/// A "Service" type is the only signal a service business without a
/// recognised category can give.
@override@JsonKey() final  String businessType;
/// Whether the shop is verified by the platform.
@override@JsonKey() final  bool isVerified;
/// Shop latitude coordinate (0 = unavailable).
@override@JsonKey() final  double latitude;
/// Shop longitude coordinate (0 = unavailable).
@override@JsonKey() final  double longitude;
/// Secondary contact (e.g. WhatsApp) if available.
@override@JsonKey() final  String secondaryPhone;
/// Email contact if available.
@override@JsonKey() final  String email;

/// Create a copy of ShopProfile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShopProfileCopyWith<_ShopProfile> get copyWith => __$ShopProfileCopyWithImpl<_ShopProfile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ShopProfileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShopProfile&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.imageUrl, imageUrl) || other.imageUrl == imageUrl)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.reviewCount, reviewCount) || other.reviewCount == reviewCount)&&(identical(other.address, address) || other.address == address)&&(identical(other.distanceInKm, distanceInKm) || other.distanceInKm == distanceInKm)&&(identical(other.openingHours, openingHours) || other.openingHours == openingHours)&&(identical(other.isOpenNow, isOpenNow) || other.isOpenNow == isOpenNow)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.about, about) || other.about == about)&&(identical(other.lastInventoryUpdate, lastInventoryUpdate) || other.lastInventoryUpdate == lastInventoryUpdate)&&const DeepCollectionEquality().equals(other._activeOffers, _activeOffers)&&const DeepCollectionEquality().equals(other._availableProducts, _availableProducts)&&(identical(other.isSaved, isSaved) || other.isSaved == isSaved)&&const DeepCollectionEquality().equals(other._categories, _categories)&&const DeepCollectionEquality().equals(other._capabilities, _capabilities)&&(identical(other.businessCategoryName, businessCategoryName) || other.businessCategoryName == businessCategoryName)&&(identical(other.businessCategoryCode, businessCategoryCode) || other.businessCategoryCode == businessCategoryCode)&&(identical(other.businessType, businessType) || other.businessType == businessType)&&(identical(other.isVerified, isVerified) || other.isVerified == isVerified)&&(identical(other.latitude, latitude) || other.latitude == latitude)&&(identical(other.longitude, longitude) || other.longitude == longitude)&&(identical(other.secondaryPhone, secondaryPhone) || other.secondaryPhone == secondaryPhone)&&(identical(other.email, email) || other.email == email));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,name,imageUrl,rating,reviewCount,address,distanceInKm,openingHours,isOpenNow,phone,about,lastInventoryUpdate,const DeepCollectionEquality().hash(_activeOffers),const DeepCollectionEquality().hash(_availableProducts),isSaved,const DeepCollectionEquality().hash(_categories),const DeepCollectionEquality().hash(_capabilities),businessCategoryName,businessCategoryCode,businessType,isVerified,latitude,longitude,secondaryPhone,email]);

@override
String toString() {
  return 'ShopProfile(id: $id, name: $name, imageUrl: $imageUrl, rating: $rating, reviewCount: $reviewCount, address: $address, distanceInKm: $distanceInKm, openingHours: $openingHours, isOpenNow: $isOpenNow, phone: $phone, about: $about, lastInventoryUpdate: $lastInventoryUpdate, activeOffers: $activeOffers, availableProducts: $availableProducts, isSaved: $isSaved, categories: $categories, capabilities: $capabilities, businessCategoryName: $businessCategoryName, businessCategoryCode: $businessCategoryCode, businessType: $businessType, isVerified: $isVerified, latitude: $latitude, longitude: $longitude, secondaryPhone: $secondaryPhone, email: $email)';
}


}

/// @nodoc
abstract mixin class _$ShopProfileCopyWith<$Res> implements $ShopProfileCopyWith<$Res> {
  factory _$ShopProfileCopyWith(_ShopProfile value, $Res Function(_ShopProfile) _then) = __$ShopProfileCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String imageUrl, double rating, int reviewCount, String address, double distanceInKm, String openingHours, bool isOpenNow, String phone, String about, DateTime lastInventoryUpdate, List<String> activeOffers, List<ShopProductSummary> availableProducts, bool isSaved, List<String> categories, List<String> capabilities, String businessCategoryName, String businessCategoryCode, String businessType, bool isVerified, double latitude, double longitude, String secondaryPhone, String email
});




}
/// @nodoc
class __$ShopProfileCopyWithImpl<$Res>
    implements _$ShopProfileCopyWith<$Res> {
  __$ShopProfileCopyWithImpl(this._self, this._then);

  final _ShopProfile _self;
  final $Res Function(_ShopProfile) _then;

/// Create a copy of ShopProfile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? imageUrl = null,Object? rating = null,Object? reviewCount = null,Object? address = null,Object? distanceInKm = null,Object? openingHours = null,Object? isOpenNow = null,Object? phone = null,Object? about = null,Object? lastInventoryUpdate = null,Object? activeOffers = null,Object? availableProducts = null,Object? isSaved = null,Object? categories = null,Object? capabilities = null,Object? businessCategoryName = null,Object? businessCategoryCode = null,Object? businessType = null,Object? isVerified = null,Object? latitude = null,Object? longitude = null,Object? secondaryPhone = null,Object? email = null,}) {
  return _then(_ShopProfile(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,imageUrl: null == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double,reviewCount: null == reviewCount ? _self.reviewCount : reviewCount // ignore: cast_nullable_to_non_nullable
as int,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,distanceInKm: null == distanceInKm ? _self.distanceInKm : distanceInKm // ignore: cast_nullable_to_non_nullable
as double,openingHours: null == openingHours ? _self.openingHours : openingHours // ignore: cast_nullable_to_non_nullable
as String,isOpenNow: null == isOpenNow ? _self.isOpenNow : isOpenNow // ignore: cast_nullable_to_non_nullable
as bool,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,about: null == about ? _self.about : about // ignore: cast_nullable_to_non_nullable
as String,lastInventoryUpdate: null == lastInventoryUpdate ? _self.lastInventoryUpdate : lastInventoryUpdate // ignore: cast_nullable_to_non_nullable
as DateTime,activeOffers: null == activeOffers ? _self._activeOffers : activeOffers // ignore: cast_nullable_to_non_nullable
as List<String>,availableProducts: null == availableProducts ? _self._availableProducts : availableProducts // ignore: cast_nullable_to_non_nullable
as List<ShopProductSummary>,isSaved: null == isSaved ? _self.isSaved : isSaved // ignore: cast_nullable_to_non_nullable
as bool,categories: null == categories ? _self._categories : categories // ignore: cast_nullable_to_non_nullable
as List<String>,capabilities: null == capabilities ? _self._capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as List<String>,businessCategoryName: null == businessCategoryName ? _self.businessCategoryName : businessCategoryName // ignore: cast_nullable_to_non_nullable
as String,businessCategoryCode: null == businessCategoryCode ? _self.businessCategoryCode : businessCategoryCode // ignore: cast_nullable_to_non_nullable
as String,businessType: null == businessType ? _self.businessType : businessType // ignore: cast_nullable_to_non_nullable
as String,isVerified: null == isVerified ? _self.isVerified : isVerified // ignore: cast_nullable_to_non_nullable
as bool,latitude: null == latitude ? _self.latitude : latitude // ignore: cast_nullable_to_non_nullable
as double,longitude: null == longitude ? _self.longitude : longitude // ignore: cast_nullable_to_non_nullable
as double,secondaryPhone: null == secondaryPhone ? _self.secondaryPhone : secondaryPhone // ignore: cast_nullable_to_non_nullable
as String,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
