import 'package:json_annotation/json_annotation.dart';

/// Kind of waiver, mirroring the backend `waiver_type` enum on
/// `gym_waivers` (`Database/python_data/schema/gym_waiver.py`).
///
/// - [payerAuth] — the gym's one protected authorized-payer agreement,
///   signed only in the link-payer flow; never attachable to a plan.
/// - [custom] — a normal gym-authored waiver, attachable to plans.
/// - [unknown] — resilient fallback for a value this build doesn't know
///   (more types may appear later); treated as non-attachable.
@JsonEnum(valueField: 'value')
enum WaiverType {
  payerAuth('payer_auth', 'Payer agreement'),
  custom('custom', 'Custom'),
  unknown('unknown', 'Unknown');

  const WaiverType(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static WaiverType fromJson(String value) {
    return WaiverType.values.firstWhere(
      (v) => v.value == value,
      orElse: () => WaiverType.unknown,
    );
  }

  String toJson() => value;
}
