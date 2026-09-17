// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'fireside_application.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FiresideApplication {

 String get id; String get name; String get department; String get description; String get category; String? get url; String? get healthUrl; String? get repository; List<String> get keywords; bool get isTall;
/// Create a copy of FiresideApplication
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FiresideApplicationCopyWith<FiresideApplication> get copyWith => _$FiresideApplicationCopyWithImpl<FiresideApplication>(this as FiresideApplication, _$identity);

  /// Serializes this FiresideApplication to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as FiresideApplication;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FiresideApplication&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.department, _this.department) || other.department == _this.department)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.category, _this.category) || other.category == _this.category)&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.healthUrl, _this.healthUrl) || other.healthUrl == _this.healthUrl)&&(identical(other.repository, _this.repository) || other.repository == _this.repository)&&const DeepCollectionEquality().equals(other.keywords, _this.keywords)&&(identical(other.isTall, _this.isTall) || other.isTall == _this.isTall));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as FiresideApplication;
  return Object.hash(runtimeType,_this.id,_this.name,_this.department,_this.description,_this.category,_this.url,_this.healthUrl,_this.repository,const DeepCollectionEquality().hash(_this.keywords),_this.isTall);
}

@override
String toString() {
  final _this = this as FiresideApplication;
  return 'FiresideApplication(id: ${_this.id}, name: ${_this.name}, department: ${_this.department}, description: ${_this.description}, category: ${_this.category}, url: ${_this.url}, healthUrl: ${_this.healthUrl}, repository: ${_this.repository}, keywords: ${_this.keywords}, isTall: ${_this.isTall})';
}


}

/// @nodoc
abstract mixin class $FiresideApplicationCopyWith<$Res>  {
  factory $FiresideApplicationCopyWith(FiresideApplication value, $Res Function(FiresideApplication) _then) = _$FiresideApplicationCopyWithImpl;
@useResult
$Res call({
 String id, String name, String department, String description, String category, String? url, String? healthUrl, String? repository, List<String> keywords, bool isTall
});




}
/// @nodoc
class _$FiresideApplicationCopyWithImpl<$Res>
    implements $FiresideApplicationCopyWith<$Res> {
  _$FiresideApplicationCopyWithImpl(this._self, this._then);

  final FiresideApplication _self;
  final $Res Function(FiresideApplication) _then;

/// Create a copy of FiresideApplication
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? department = null,Object? description = null,Object? category = null,Object? url = freezed,Object? healthUrl = freezed,Object? repository = freezed,Object? keywords = null,Object? isTall = null,}) {
  return _then(FiresideApplication(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,department: null == department ? _self.department : department // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,healthUrl: freezed == healthUrl ? _self.healthUrl : healthUrl // ignore: cast_nullable_to_non_nullable
as String?,repository: freezed == repository ? _self.repository : repository // ignore: cast_nullable_to_non_nullable
as String?,keywords: null == keywords ? _self.keywords : keywords // ignore: cast_nullable_to_non_nullable
as List<String>,isTall: null == isTall ? _self.isTall : isTall // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [FiresideApplication].
extension FiresideApplicationPatterns on FiresideApplication {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FiresideApplication value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FiresideApplication() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FiresideApplication value)  $default,){
final _that = this;
switch (_that) {
case _FiresideApplication():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FiresideApplication value)?  $default,){
final _that = this;
switch (_that) {
case _FiresideApplication() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String department,  String description,  String category,  String? url,  String? healthUrl,  String? repository,  List<String> keywords,  bool isTall)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FiresideApplication() when $default != null:
return $default(_that.id,_that.name,_that.department,_that.description,_that.category,_that.url,_that.healthUrl,_that.repository,_that.keywords,_that.isTall);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String department,  String description,  String category,  String? url,  String? healthUrl,  String? repository,  List<String> keywords,  bool isTall)  $default,) {final _that = this;
switch (_that) {
case _FiresideApplication():
return $default(_that.id,_that.name,_that.department,_that.description,_that.category,_that.url,_that.healthUrl,_that.repository,_that.keywords,_that.isTall);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String department,  String description,  String category,  String? url,  String? healthUrl,  String? repository,  List<String> keywords,  bool isTall)?  $default,) {final _that = this;
switch (_that) {
case _FiresideApplication() when $default != null:
return $default(_that.id,_that.name,_that.department,_that.description,_that.category,_that.url,_that.healthUrl,_that.repository,_that.keywords,_that.isTall);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FiresideApplication implements FiresideApplication {
  const _FiresideApplication({required this.id, required this.name, required this.department, required this.description, required this.category, this.url, this.healthUrl, this.repository,  List<String> keywords = const <String>[], this.isTall = false}): _keywords = keywords;
  factory _FiresideApplication.fromJson(Map<String, dynamic> json) => _$FiresideApplicationFromJson(json);

@override final  String id;
@override final  String name;
@override final  String department;
@override final  String description;
@override final  String category;
@override final  String? url;
@override final  String? healthUrl;
@override final  String? repository;
 final  List<String> _keywords;
@override@JsonKey() List<String> get keywords {
  if (_keywords is EqualUnmodifiableListView) return _keywords;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_keywords);
}

@override@JsonKey() final  bool isTall;

/// Create a copy of FiresideApplication
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FiresideApplicationCopyWith<_FiresideApplication> get copyWith => __$FiresideApplicationCopyWithImpl<_FiresideApplication>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FiresideApplicationToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FiresideApplication&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.department, department) || other.department == department)&&(identical(other.description, description) || other.description == description)&&(identical(other.category, category) || other.category == category)&&(identical(other.url, url) || other.url == url)&&(identical(other.healthUrl, healthUrl) || other.healthUrl == healthUrl)&&(identical(other.repository, repository) || other.repository == repository)&&const DeepCollectionEquality().equals(other.keywords, _keywords)&&(identical(other.isTall, isTall) || other.isTall == isTall));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,department,description,category,url,healthUrl,repository,const DeepCollectionEquality().hash(_keywords),isTall);
}

@override
String toString() {
    return 'FiresideApplication(id: $id, name: $name, department: $department, description: $description, category: $category, url: $url, healthUrl: $healthUrl, repository: $repository, keywords: $keywords, isTall: $isTall)';
}


}

/// @nodoc
abstract mixin class _$FiresideApplicationCopyWith<$Res> implements $FiresideApplicationCopyWith<$Res> {
  factory _$FiresideApplicationCopyWith(_FiresideApplication value, $Res Function(_FiresideApplication) _then) = __$FiresideApplicationCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String department, String description, String category, String? url, String? healthUrl, String? repository, List<String> keywords, bool isTall
});




}
/// @nodoc
class __$FiresideApplicationCopyWithImpl<$Res>
    implements _$FiresideApplicationCopyWith<$Res> {
  __$FiresideApplicationCopyWithImpl(this._self, this._then);

  final _FiresideApplication _self;
  final $Res Function(_FiresideApplication) _then;

/// Create a copy of FiresideApplication
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? department = null,Object? description = null,Object? category = null,Object? url = freezed,Object? healthUrl = freezed,Object? repository = freezed,Object? keywords = null,Object? isTall = null,}) {
  return _then(_FiresideApplication(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,department: null == department ? _self.department : department // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,healthUrl: freezed == healthUrl ? _self.healthUrl : healthUrl // ignore: cast_nullable_to_non_nullable
as String?,repository: freezed == repository ? _self.repository : repository // ignore: cast_nullable_to_non_nullable
as String?,keywords: null == keywords ? _self._keywords : keywords // ignore: cast_nullable_to_non_nullable
as List<String>,isTall: null == isTall ? _self.isTall : isTall // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
