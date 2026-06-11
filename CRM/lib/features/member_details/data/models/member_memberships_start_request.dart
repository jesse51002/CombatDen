import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/member_memberships_start_item.dart';

part 'member_memberships_start_request.g.dart';

/// Body for `POST /api/v1/member_memberships/` and its
/// `/preview` counterpart.
///
/// Mirrors the list-based backend
/// `MemberMembershipsStartRequest`: one request starts a
/// payer's family memberships together. The payer
/// ([payerMemberId]) is identity-only — it need not appear
/// in [memberships]; every non-payer member must ALREADY be
/// linked to the payer. [prorate] applies to the recurring
/// converge only; [paidWithCash] is request-level. The
/// single [idempotencyKey] dedups both charge groups at
/// Stripe on a client retry.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  explicitToJson: true,
)
class MemberMembershipsStartRequest extends Equatable {
  final String payerMemberId;
  final String gymId;
  final bool prorate;
  final bool paidWithCash;
  final String idempotencyKey;
  final List<MemberMembershipsStartItem> memberships;

  const MemberMembershipsStartRequest({
    required this.payerMemberId,
    required this.gymId,
    required this.idempotencyKey,
    required this.memberships,
    this.prorate = true,
    this.paidWithCash = false,
  });

  MemberMembershipsStartRequest copyWith({
    String? payerMemberId,
    String? gymId,
    bool? prorate,
    bool? paidWithCash,
    String? idempotencyKey,
    List<MemberMembershipsStartItem>? memberships,
  }) {
    return MemberMembershipsStartRequest(
      payerMemberId:
          payerMemberId ?? this.payerMemberId,
      gymId: gymId ?? this.gymId,
      prorate: prorate ?? this.prorate,
      paidWithCash: paidWithCash ?? this.paidWithCash,
      idempotencyKey:
          idempotencyKey ?? this.idempotencyKey,
      memberships: memberships ?? this.memberships,
    );
  }

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsStartRequestToJson(this);

  @override
  List<Object?> get props => [
        payerMemberId,
        gymId,
        prorate,
        paidWithCash,
        idempotencyKey,
        memberships,
      ];
}
