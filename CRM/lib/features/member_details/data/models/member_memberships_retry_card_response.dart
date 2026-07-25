import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/member_memberships_retry_card_status.dart';

part 'member_memberships_retry_card_response.g.dart';

/// Outcome of `POST /api/v1/member_memberships/retry-card`.
///
/// Mirrors the backend `MemberMembershipsRetryCardResponse`.
/// The bank's answer is DATA, not an error: `paid` arrives on
/// a 200 (the open invoice is settled), `declined` on a 207
/// with [declineReason] carrying Stripe's own end-user wording
/// (expired card, insufficient funds) — nothing was collected
/// and the membership stays overdue. A system/upstream failure
/// is NOT this shape; it still rides a 500 as a `ServerException`.
///
/// [isPaid] is the ONLY way to read success: anything else —
/// including an [MemberMembershipsRetryCardStatus.unknown]
/// value from a newer backend — is fail-closed, so a decline
/// can never render as a collected charge.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MemberMembershipsRetryCardResponse extends Equatable {
  final String itemId;
  final String memberId;
  @JsonKey(fromJson: MemberMembershipsRetryCardStatus.fromJson)
  final MemberMembershipsRetryCardStatus status;
  final String? declineReason;

  const MemberMembershipsRetryCardResponse({
    required this.itemId,
    required this.memberId,
    required this.status,
    this.declineReason,
  });

  factory MemberMembershipsRetryCardResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MemberMembershipsRetryCardResponseFromJson(json);

  /// True ONLY for an explicitly collected charge.
  bool get isPaid =>
      status == MemberMembershipsRetryCardStatus.paid;

  @override
  List<Object?> get props => [
        itemId,
        memberId,
        status,
        declineReason,
      ];
}
