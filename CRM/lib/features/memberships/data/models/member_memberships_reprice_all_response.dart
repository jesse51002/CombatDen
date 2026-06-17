import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_memberships_reprice_all_response.g.dart';

/// Response from `POST /api/v1/member_memberships/reprice-plan`.
/// [taskId] is nullable — null means everyone is already on the
/// latest price (nothing to upgrade).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MemberMembershipsRepriceAllResponse extends Equatable {
  final String? taskId;
  final int membershipCount;

  const MemberMembershipsRepriceAllResponse({
    this.taskId,
    required this.membershipCount,
  });

  factory MemberMembershipsRepriceAllResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MemberMembershipsRepriceAllResponseFromJson(json);

  @override
  List<Object?> get props => [taskId, membershipCount];
}
