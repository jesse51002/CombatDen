import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'members_management_link_request.g.dart';

/// Body for `PUT /api/v1/members/{member_id}/link`
/// and its `/link/check` + `/link/preview` counterparts.
///
/// Mirrors the merged `MembersBillingLinkRequest` schema
/// (`parent_member_id`).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MembersManagementLinkRequest extends Equatable {
  final String parentMemberId;

  const MembersManagementLinkRequest({
    required this.parentMemberId,
  });

  Map<String, dynamic> toJson() =>
      _$MembersManagementLinkRequestToJson(this);

  @override
  @JsonKey(includeToJson: false)
  List<Object?> get props => [parentMemberId];

  @override
  @JsonKey(includeToJson: false)
  bool? get stringify => super.stringify;

  @override
  @JsonKey(includeToJson: false)
  int get hashCode => super.hashCode; // ignore: hash_and_equals
}
