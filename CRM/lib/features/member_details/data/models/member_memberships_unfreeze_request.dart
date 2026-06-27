import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_memberships_unfreeze_request.g.dart';

/// Body for `POST /api/v1/member_memberships/unfreeze`.
///
/// Matches the merged `MemberMembershipsUnfreezeRequest`
/// schema (member-id keyed).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MemberMembershipsUnfreezeRequest extends Equatable {
  final String memberId;
  final String gymId;
  final String idempotencyKey;

  const MemberMembershipsUnfreezeRequest({
    required this.memberId,
    required this.gymId,
    required this.idempotencyKey,
  });

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsUnfreezeRequestToJson(this);

  @override
  @JsonKey(includeToJson: false)
  List<Object?> get props =>
      [memberId, gymId, idempotencyKey];

  @override
  @JsonKey(includeToJson: false)
  bool? get stringify => super.stringify;

  @override
  @JsonKey(includeToJson: false)
  int get hashCode => super.hashCode; // ignore: hash_and_equals
}
