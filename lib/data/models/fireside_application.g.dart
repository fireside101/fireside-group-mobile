// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fireside_application.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FiresideApplication _$FiresideApplicationFromJson(Map<String, dynamic> json) =>
    _FiresideApplication(
      id: json['id'] as String,
      name: json['name'] as String,
      department: json['department'] as String,
      description: json['description'] as String,
      category: json['category'] as String,
      url: json['url'] as String?,
      healthUrl: json['healthUrl'] as String?,
      repository: json['repository'] as String?,
      keywords:
          (json['keywords'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      isTall: json['isTall'] as bool? ?? false,
    );

Map<String, dynamic> _$FiresideApplicationToJson(
  _FiresideApplication instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'department': instance.department,
  'description': instance.description,
  'category': instance.category,
  'url': instance.url,
  'healthUrl': instance.healthUrl,
  'repository': instance.repository,
  'keywords': instance.keywords,
  'isTall': instance.isTall,
};
