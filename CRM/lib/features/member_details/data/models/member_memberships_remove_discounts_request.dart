import 'package:equatable/equatable.dart';

/// Body for `POST /api/v1/member_memberships/discounts/remove`.
///
/// Mirrors the backend `MemberMembershipsRemoveDiscountsRequest`: deletes the
/// applied-discount snapshots named by their `applied_discount_id`
/// ([appliedIds]). When [preview] is true the backend stages the removal,
/// returns the resulting invoice preview, and reverts (nothing committed);
/// otherwise it commits and re-syncs.
class MemberMembershipsRemoveDiscountsRequest extends Equatable {
  final String itemId;
  final String memberId;
  final List<String> appliedIds;
  final String idempotencyKey;
  final bool preview;

  const MemberMembershipsRemoveDiscountsRequest({
    required this.itemId,
    required this.memberId,
    required this.appliedIds,
    required this.idempotencyKey,
    this.preview = false,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'item_id': itemId,
        'member_id': memberId,
        'applied_ids': appliedIds,
        'idempotency_key': idempotencyKey,
        'preview': preview,
      };

  @override
  List<Object?> get props => [
        itemId,
        memberId,
        appliedIds,
        idempotencyKey,
        preview,
      ];
}
