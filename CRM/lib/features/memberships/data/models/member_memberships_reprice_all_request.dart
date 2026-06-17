import 'package:json_annotation/json_annotation.dart';

part 'member_memberships_reprice_all_request.g.dart';

/// Body for `POST /api/v1/member_memberships/reprice-plan`.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class MemberMembershipsRepriceAllRequest {
  final String planId;
  final String gymId;
  final bool prorate;

  const MemberMembershipsRepriceAllRequest({
    required this.planId,
    required this.gymId,
    this.prorate = false,
  });

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsRepriceAllRequestToJson(this);
}
