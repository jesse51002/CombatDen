import 'package:json_annotation/json_annotation.dart';

/// Outcome of a card retry on ONE membership's open invoice.
///
/// Mirrors the backend `MemberMembershipsRetryCardStatus`:
/// `paid` arrives on a 200; `declined` and [notCollected] both
/// arrive on a 207, because neither is a server failure — a bank
/// refusal is a RESULT, and so is "nobody refused, but the money
/// did not move". [unknown] is the fail-closed fallback for a
/// value this build doesn't know — never treated as a collected
/// charge.
///
/// **[declined] and [notCollected] are different facts and the
/// desk acts on them differently.** Declined is the bank saying
/// no: try another card. Not-collected is the charge needing
/// authorization only the member can complete, so no amount of
/// retrying at the desk will settle it — the reason string says
/// so, and collecting another way is the answer. Folding the two
/// together would send staff round a retry loop that cannot win.
@JsonEnum(valueField: 'value')
enum MemberMembershipsRetryCardStatus {
  paid('paid', 'Paid'),
  declined('declined', 'Declined'),
  notCollected('not_collected', 'Not collected'),
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
