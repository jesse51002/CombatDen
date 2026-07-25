import 'package:json_annotation/json_annotation.dart';

/// Outcome of a card retry on ONE membership's open invoice.
///
/// Mirrors the backend `MemberMembershipsRetryCardStatus`:
/// `paid` arrives on a 200, `declined` on a 207 (a bank
/// refusal is a RESULT, not a server failure). [unknown] is
/// the fail-closed fallback for a value this build doesn't
/// know — never treated as a collected charge.
@JsonEnum(valueField: 'value')
enum MemberMembershipsRetryCardStatus {
  paid('paid', 'Paid'),
  declined('declined', 'Declined'),
  unknown('unknown', 'Unknown');

  const MemberMembershipsRetryCardStatus(
    this.value,
    this.displayLabel,
  );

  final String value;
  final String displayLabel;

  static MemberMembershipsRetryCardStatus fromJson(
    String value,
  ) {
    return MemberMembershipsRetryCardStatus.values.firstWhere(
      (v) => v.value == value,
      orElse: () => MemberMembershipsRetryCardStatus.unknown,
    );
  }

  String toJson() => value;
}
