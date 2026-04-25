import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_memberships_unfreeze_request.g.dart';

/// Body for `POST /api/v1/member_memberships/unfreeze`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MemberMembershipsUnfreezeRequest extends Equatable {
  final String crmUserId;
  final String gymId;
  final String idempotencyKey;

  const MemberMembershipsUnfreezeRequest({
    required this.crmUserId,
    required this.gymId,
    required this.idempotencyKey,
  });

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsUnfreezeRequestToJson(this);

  @override
  List<Object?> get props =>
      [crmUserId, gymId, idempotencyKey];
}
