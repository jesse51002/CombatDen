import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_memberships_freeze_request.g.dart';

/// Body for `POST /api/v1/member_memberships/freeze`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MemberMembershipsFreezeRequest extends Equatable {
  final String crmUserId;
  final String gymId;
  final int freezeMonths;
  final String idempotencyKey;

  const MemberMembershipsFreezeRequest({
    required this.crmUserId,
    required this.gymId,
    required this.freezeMonths,
    required this.idempotencyKey,
  });

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsFreezeRequestToJson(this);

  @override
  List<Object?> get props => [
        crmUserId,
        gymId,
        freezeMonths,
        idempotencyKey,
      ];
}
