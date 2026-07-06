import 'package:json_annotation/json_annotation.dart';

/// A gym's per-gym sub-rank type — mirrors the Postgres
/// `sub_rank_type` enum (`none` | `stripes` | `div`). Drives how every
/// sub-rank LABEL is derived from a leaf's `sub_index`; labels are
/// never stored (see `Database/python_data/schema/gym_rank.py`'s
/// `sub_rank_label`, which this mirrors).
///
/// `none` turns sub-positions OFF gym-wide: the ladder shows main belts
/// only (no stripe/division row), and members carry no sub-index. It is
/// a first-class enum value, not the absence of one.
@JsonEnum(valueField: 'value')
enum RankSubType {
  none('none'),
  stripes('stripes'),
  div('div'),
  unknown('unknown');

  const RankSubType(this.value);

  /// The snake_case value used in JSON serialization.
  final String value;

  /// Parses a JSON string into a [RankSubType]. Falls back to
  /// [unknown] for unrecognised values so the app stays resilient
  /// when the backend adds a new sub-rank type.
  static RankSubType fromJson(String value) {
    return RankSubType.values.firstWhere(
      (v) => v.value == value,
      orElse: () => RankSubType.unknown,
    );
  }

  /// [fromJson] for a nullable value (e.g. a preset's
  /// `implied_sub_rank_type`, which is `null` when the preset has no
  /// sub-ranks).
  static RankSubType? fromJsonNullable(String? value) =>
      value == null ? null : RankSubType.fromJson(value);

  /// Converts to a JSON string.
  String toJson() => value;

  /// The derived label for leaf [index] under this sub-rank type.
  ///
  /// None: always `''` — a `none` gym has no sub-positions, so this is
  /// a guard against a stray call (callers gate the sub-rank UI on the
  /// type first and never render a labelled sub for a `none` gym).
  /// Stripes: `0` -> `''` (the bare belt name, no suffix), `1` ->
  /// `'1 Stripe'`, `k` -> `'k Stripes'`. Div: `i` -> `'Div ${i + 1}'`
  /// (1-indexed display over a 0-indexed `sub_index`). `unknown`
  /// falls back to the stripes rule so a forward-compatible gym type
  /// still renders something sensible.
  String subLabel(int index) {
    if (this == RankSubType.none) return '';
    if (this == RankSubType.div) return 'Div ${index + 1}';
    if (index == 0) return '';
    return index == 1 ? '1 Stripe' : '$index Stripes';
  }

  /// [subLabel] for a nullable index — a rank with no sub-ranks (or a
  /// member on the base leaf of a subless rank) has no label at all.
  String? subLabelOrNull(int? index) =>
      index == null ? null : subLabel(index);
}
