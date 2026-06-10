import 'package:equatable/equatable.dart';

/// Body for `POST /api/v1/member_memberships/discounts/add`.
///
/// Mirrors the backend `MemberMembershipsAddDiscountsRequest`: adds a frozen
/// snapshot per named preset ([discountIds], by discount id — any type, including
/// a `linked` family discount) at its active value version. When [preview] is
/// true the backend stages the add, returns the resulting invoice preview, and
/// rolls back (nothing committed); otherwise it commits and re-syncs.
class MemberMembershipsAddDiscountsRequest extends Equatable {
  final String itemId;
  final String memberId;
  final List<String> discountIds;
  final String idempotencyKey;
  final bool preview;

  const MemberMembershipsAddDiscountsRequest({
    required this.itemId,
    required this.memberId,
    required this.discountIds,
    required this.idempotencyKey,
    this.preview = false,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'item_id': itemId,
        'member_id': memberId,
        'discount_ids': discountIds,
        'idempotency_key': idempotencyKey,
        'preview': preview,
      };

  @override
  List<Object?> get props => [
        itemId,
        memberId,
        discountIds,
        idempotencyKey,
        preview,
      ];
}
