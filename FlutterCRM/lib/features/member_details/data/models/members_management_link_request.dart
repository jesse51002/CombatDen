import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'members_management_link_request.g.dart';

/// Body for `PUT /api/v1/members/{crm_user_id}/link`
/// and its `/link/preview` counterpart.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MembersManagementLinkRequest extends Equatable {
  final String parentCrmUserId;

  const MembersManagementLinkRequest({
    required this.parentCrmUserId,
  });

  Map<String, dynamic> toJson() =>
      _$MembersManagementLinkRequestToJson(this);

  @override
  List<Object?> get props => [parentCrmUserId];
}
