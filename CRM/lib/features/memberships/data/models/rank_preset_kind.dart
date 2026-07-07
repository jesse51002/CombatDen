import 'package:json_annotation/json_annotation.dart';

/// The three rank preset ladders — mirrors the Postgres
/// `rank_preset_kind` enum: BJJ belts (no stripes), BJJ belts with
/// stripes, and one generic flat tier ladder.
@JsonEnum(valueField: 'value')
enum RankPresetKind {
  bjjBelts('bjj_belts', 'BJJ Belts'),
  bjjBeltsStripes('bjj_belts_stripes', 'BJJ Belts + Stripes'),
  flat('flat', 'Flat Tiers'),
  unknown('unknown', 'Unknown');

  const RankPresetKind(this.value, this.displayLabel);

  /// The snake_case value used in JSON serialization.
  final String value;

  /// Human-readable label for the UI.
  final String displayLabel;

  /// Parses a JSON string into a [RankPresetKind]. Falls back to
  /// [unknown] for unrecognised values so the app stays resilient
  /// when the backend adds a new preset kind.
  static RankPresetKind fromJson(String value) {
    return RankPresetKind.values.firstWhere(
      (v) => v.value == value,
      orElse: () => RankPresetKind.unknown,
    );
  }

  /// Converts to a JSON string.
  String toJson() => value;
}
