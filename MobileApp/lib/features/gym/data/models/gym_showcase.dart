import 'package:json_annotation/json_annotation.dart';

part 'gym_showcase.g.dart';

/// A gym's showcase payload — only the fields the mobile app needs to re-theme
/// itself to the gym's branding.
///
/// Mirrors `GymShowcase` in
/// `FastApiBackend/src/theme/schema/theme_schema.py`. The backend's `classes` /
/// `rewards` lists are intentionally NOT modelled here (Phase E reads those
/// through the feature repositories); json_serializable ignores those unknown
/// keys on parse. [themeDesignId] is the load-bearing field: the gym's saved
/// ThemeService design id, applied via `ThemeRuntime.selectDesign`. Null until
/// the gym has picked a theme.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class GymShowcase {
  final String gymId;
  final String? themeDesignId;

  const GymShowcase({
    required this.gymId,
    this.themeDesignId,
  });

  factory GymShowcase.fromJson(Map<String, dynamic> json) =>
      _$GymShowcaseFromJson(json);
}
