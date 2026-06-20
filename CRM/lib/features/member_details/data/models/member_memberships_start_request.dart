import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/member_memberships_start_item.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_payment.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';

part 'member_memberships_start_request.g.dart';

/// Body for `POST /api/v1/member_memberships/` and its
/// `/preview` counterpart.
///
/// Mirrors the list-based backend
/// `MemberMembershipsStartRequest`: one request starts a
/// payer's family memberships together. The payer
/// ([payerMemberId]) is identity-only — it need not appear
/// in [memberships]; every non-payer member must ALREADY be
/// linked to the payer. [prorationBehavior] applies to the
/// recurring converge only; [paidWithCash] is request-level.
/// The single [idempotencyKey] dedups both charge groups at
/// Stripe on a client retry.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  explicitToJson: true,
)
class MemberMembershipsStartRequest {
  final String payerMemberId;
  final String gymId;
  final ProrationBehavior prorationBehavior;
  final bool paidWithCash;

  /// An optional card entered at checkout. Set only on PAY,
  /// never on a preview.
  final MemberMembershipsStartPayment? payment;
  final String idempotencyKey;
  final List<MemberMembershipsStartItem> memberships;

  const MemberMembershipsStartRequest({
    required this.payerMemberId,
    required this.gymId,
    required this.idempotencyKey,
    required this.memberships,
    this.prorationBehavior = ProrationBehavior.prorateToAnchor,
    this.paidWithCash = false,
    this.payment,
  });

  MemberMembershipsStartRequest copyWith({
    String? payerMemberId,
    String? gymId,
    ProrationBehavior? prorationBehavior,
    bool? paidWithCash,
    MemberMembershipsStartPayment? payment,
    String? idempotencyKey,
    List<MemberMembershipsStartItem>? memberships,
  }) {
    return MemberMembershipsStartRequest(
      payerMemberId:
          payerMemberId ?? this.payerMemberId,
      gymId: gymId ?? this.gymId,
      prorationBehavior:
          prorationBehavior ?? this.prorationBehavior,
      paidWithCash: paidWithCash ?? this.paidWithCash,
      payment: payment ?? this.payment,
      idempotencyKey:
          idempotencyKey ?? this.idempotencyKey,
      memberships: memberships ?? this.memberships,
    );
  }

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsStartRequestToJson(this);
}
