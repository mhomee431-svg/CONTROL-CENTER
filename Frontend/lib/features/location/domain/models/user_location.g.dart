// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_location.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_UserLocation _$UserLocationFromJson(Map<String, dynamic> json) =>
    _UserLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      pincode: json['pincode'] as String? ?? '',
      label: json['label'] as String? ?? '',
      isManual: json['isManual'] as bool? ?? false,
      isApproximate: json['isApproximate'] as bool? ?? false,
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble() ?? 0.0,
      isSelected: json['isSelected'] as bool? ?? false,
      capturedAtMs: (json['capturedAtMs'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$UserLocationToJson(_UserLocation instance) =>
    <String, dynamic>{
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'address': instance.address,
      'city': instance.city,
      'state': instance.state,
      'pincode': instance.pincode,
      'label': instance.label,
      'isManual': instance.isManual,
      'isApproximate': instance.isApproximate,
      'accuracyMeters': instance.accuracyMeters,
      'isSelected': instance.isSelected,
      'capturedAtMs': instance.capturedAtMs,
    };
