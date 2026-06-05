import 'package:equatable/equatable.dart';

/// Body for `PUT /api/v1/member_memberships/discounts`.
///
/// Mirrors the backend `MemberMembershipsApplyDiscountsRequest`: applying a
/// discount is an explicit add / remove of immutable snapshot rows. [addPresetIds]
/// references live discounts by id (any type, including a `linked` family
/// discount); each frozen onto a snapshot at its active value version.
/// [removeAppliedIds] deletes snapshots by their `applied_discount_id`. The
/// request must add or remove at least one discount.
class MemberMembershipsApplyDiscountsRequest extends Equatable {
  final String itemId;
  final String memberId;
  final List<String> addPresetIds;
  final List<String> removeAppliedIds;
  final String idempotencyKey;

  const MemberMembershipsApplyDiscountsRequest({
    required this.itemId,
    required this.memberId,
    this.addPresetIds = const [],
    this.removeAppliedIds = const [],
    required this.idempotencyKey,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'item_id': itemId,
        'member_id': memberId,
        'add_preset_ids': addPresetIds,
        'remove_applied_ids': removeAppliedIds,
        'idempotency_key': idempotencyKey,
      };

  @override
  List<Object?> get props => [
        itemId,
        memberId,
        addPresetIds,
        removeAppliedIds,
        idempotencyKey,
      ];
}
