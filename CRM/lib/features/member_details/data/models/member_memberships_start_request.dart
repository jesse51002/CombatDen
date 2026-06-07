import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_memberships_start_request.g.dart';

/// Body for `POST /api/v1/member_memberships/` and its
/// `/preview` counterpart.
///
/// Mirrors the reshaped `MemberMembershipsStartRequest`:
/// memberships are created discount-free — discounts are
/// applied as immutable snapshots afterward via the apply
/// path (`PUT /discounts`), not threaded in at creation. The
/// old `discount_ids` / `include_linked_discount` fields are
/// gone.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  includeIfNull: false,
)
class MemberMembershipsStartRequest extends Equatable {
  final String memberId;
  final String gymId;
  final String planId;
  final String priceId;
  final bool prorate;
  final bool paidWithCash;
  final String idempotencyKey;

  const MemberMembershipsStartRequest({
    required this.memberId,
    required this.gymId,
    required this.planId,
    required this.priceId,
    required this.idempotencyKey,
    this.prorate = true,
    this.paidWithCash = false,
  });

  MemberMembershipsStartRequest copyWith({
    String? memberId,
    String? gymId,
    String? planId,
    String? priceId,
    bool? prorate,
    bool? paidWithCash,
    String? idempotencyKey,
  }) {
    return MemberMembershipsStartRequest(
      memberId: memberId ?? this.memberId,
      gymId: gymId ?? this.gymId,
      planId: planId ?? this.planId,
      priceId: priceId ?? this.priceId,
      prorate: prorate ?? this.prorate,
      paidWithCash: paidWithCash ?? this.paidWithCash,
      idempotencyKey:
          idempotencyKey ?? this.idempotencyKey,
    );
  }

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsStartRequestToJson(this);

  @override
  List<Object?> get props => [
        memberId,
        gymId,
        planId,
        priceId,
        prorate,
        paidWithCash,
        idempotencyKey,
      ];
}
