import 'package:freezed_annotation/freezed_annotation.dart';

part 'fireside_application.freezed.dart';
part 'fireside_application.g.dart';

@freezed
abstract class FiresideApplication with _$FiresideApplication {
  const factory FiresideApplication({
    required String id,
    required String name,
    required String department,
    required String description,
    required String category,
    String? url,
    String? healthUrl,
    String? repository,
    @Default(<String>[]) List<String> keywords,
    @Default(false) bool isTall,
  }) = _FiresideApplication;

  factory FiresideApplication.fromJson(Map<String, dynamic> json) =>
      _$FiresideApplicationFromJson(json);
}