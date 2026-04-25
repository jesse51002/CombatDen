import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_memberships_mark_paid_cash_request.g.dart';

/// Body for `POST /api/v1/member_memberships/mark-paid-cash`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MemberMembershipsMarkPaidCashRequest extends Equatable {
  final String itemId;
  final String crmUserId;
  final String idempotencyKey;

  const MemberMembershipsMarkPaidCashRequest({
    required this.itemId,
    required this.crmUserId,
    required this.idempotencyKey,
  });

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsMarkPaidCashRequestToJson(this);

  @override
  List<Object?> get props => [
        itemId,
        crmUserId,
        idempotencyKey,
      ];
}
