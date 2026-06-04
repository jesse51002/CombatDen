import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_memberships_start_request.g.dart';

/// Body for `POST /api/v1/member_memberships/` and its
/// `/preview` counterpart.
///
/// Matches the merged `MemberMembershipsStartRequest`
/// schema (member-id keyed).
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
  final List<String>? discountIds;
  final bool includeLinkedDiscount;
  final bool prorate;
  final bool paidWithCash;
  final String idempotencyKey;

  const MemberMembershipsStartRequest({
    required this.memberId,
    required this.gymId,
    required this.planId,
    required this.priceId,
    required this.idempotencyKey,
    this.discountIds,
    this.includeLinkedDiscount = false,
    this.prorate = true,
    this.paidWithCash = false,
  });

  MemberMembershipsStartRequest copyWith({
    String? memberId,
    String? gymId,
    String? planId,
    String? priceId,
    List<String>? discountIds,
    bool? includeLinkedDiscount,
    bool? prorate,
    bool? paidWithCash,
    String? idempotencyKey,
  }) {
    return MemberMembershipsStartRequest(
      memberId: memberId ?? this.memberId,
      gymId: gymId ?? this.gymId,
      planId: planId ?? this.planId,
      priceId: priceId ?? this.priceId,
      discountIds: discountIds ?? this.discountIds,
      includeLinkedDiscount: includeLinkedDiscount ??
          this.includeLinkedDiscount,
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
        discountIds,
        includeLinkedDiscount,
        prorate,
        paidWithCash,
        idempotencyKey,
      ];
}
