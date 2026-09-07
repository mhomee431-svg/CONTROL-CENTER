// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'saved_address.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SavedAddress _$SavedAddressFromJson(Map<String, dynamic> json) =>
    _SavedAddress(
      id: json['id'] as String,
      label: json['label'] as String,
      location: UserLocation.fromJson(json['location'] as Map<String, dynamic>),
      isSelected: json['isSelected'] as bool? ?? false,
      savedAtMs: (json['savedAtMs'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$SavedAddressToJson(_SavedAddress instance) =>
    <String, dynamic>{
      'id': instance.id,
      'label': instance.label,
      'location': instance.location,
      'isSelected': instance.isSelected,
      'savedAtMs': instance.savedAtMs,
    };
