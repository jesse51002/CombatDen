import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'members_management_link_check_response.g.dart';

/// Response from `POST /api/v1/members/{crm_user_id}/link/check`.
///
/// `error` is a pre-formatted, user-facing string — render it
/// as-is when `canLink` is false.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MembersManagementLinkCheckResponse extends Equatable {
  final bool canLink;
  final String? error;

  const MembersManagementLinkCheckResponse({
    required this.canLink,
    this.error,
  });

  factory MembersManagementLinkCheckResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MembersManagementLinkCheckResponseFromJson(json);

  @override
  List<Object?> get props => [canLink, error];
}
