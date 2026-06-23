import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_memberships_freeze_request.g.dart';

/// Body for `POST /api/v1/member_memberships/freeze`.
///
/// Matches the merged `MemberMembershipsFreezeRequest`
/// schema (member-id keyed).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MemberMembershipsFreezeRequest extends Equatable {
  final String memberId;
  final String gymId;
  final int freezeMonths;
  final String idempotencyKey;

  const MemberMembershipsFreezeRequest({
    required this.memberId,
    required this.gymId,
    required this.freezeMonths,
    required this.idempotencyKey,
  });

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsFreezeRequestToJson(this);

  @override
  @JsonKey(includeToJson: false)
  List<Object?> get props => [
        memberId,
        gymId,
        freezeMonths,
        idempotencyKey,
      ];

  @override
  @JsonKey(includeToJson: false)
  bool? get stringify => super.stringify;

  @override
  @JsonKey(includeToJson: false)
  int get hashCode => super.hashCode; // ignore: hash_and_equals
}
