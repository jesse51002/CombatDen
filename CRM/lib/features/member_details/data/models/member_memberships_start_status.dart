import 'package:json_annotation/json_annotation.dart';

/// Outcome of one membership inside a start request.
///
/// Mirrors the backend `MemberMembershipsStartStatus`.
@JsonEnum(valueField: 'value')
enum MemberMembershipsStartStatus {
  created('created', 'Created'),
  failed('failed', 'Failed'),
  unknown('unknown', 'Unknown');

  const MemberMembershipsStartStatus(
    this.value,
    this.displayLabel,
  );

  final String value;
  final String displayLabel;

  static MemberMembershipsStartStatus fromJson(
    String value,
  ) {
    return MemberMembershipsStartStatus.values.firstWhere(
      (v) => v.value == value,
      orElse: () => MemberMembershipsStartStatus.unknown,
    );
  }

  String toJson() => value;
}
