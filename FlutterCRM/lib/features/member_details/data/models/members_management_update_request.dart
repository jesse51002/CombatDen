import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'members_management_update_request.g.dart';

/// Body for `PUT /api/v1/members/{crm_user_id}`. Every
/// field is optional — only the fields present in the
/// request are updated.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  includeIfNull: false,
)
class MembersManagementUpdateRequest extends Equatable {
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? email;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? emergencyContactEmail;
  final String? accountLinkedToId;

  const MembersManagementUpdateRequest({
    this.firstName,
    this.lastName,
    this.phone,
    this.email,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.emergencyContactEmail,
    this.accountLinkedToId,
  });

  Map<String, dynamic> toJson() =>
      _$MembersManagementUpdateRequestToJson(this);

  @override
  List<Object?> get props => [
        firstName,
        lastName,
        phone,
        email,
        address,
        emergencyContactName,
        emergencyContactPhone,
        emergencyContactEmail,
        accountLinkedToId,
      ];
}
