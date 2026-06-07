import 'package:equatable/equatable.dart';

/// Body for `PUT /api/v1/members/{member_id}`.
///
/// Mirrors `MemberUpdateRequest`, which wraps the editable
/// fields in a `data` object (`MemberUpdateData`). Every
/// field is optional — only the fields present in the
/// request are updated.
///
/// Contract note: the merged `MemberUpdateData` schema
/// accepts identity (name / email / current rank) **and**
/// the contact / profile columns (phone, address, the
/// three emergency-contact fields, photo URL). The backend
/// writes them via its privileged connection, so the
/// `REVOKE … FROM authenticated` column grants on `members`
/// (which only gate direct Supabase clients) don't apply.
/// Account linking still goes through the dedicated
/// `/members/{member_id}/link` endpoints, not here.
class MembersManagementUpdateRequest extends Equatable {
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? currentRankId;
  final String? phone;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? emergencyContactEmail;
  final String? photoUrl;

  const MembersManagementUpdateRequest({
    this.firstName,
    this.lastName,
    this.email,
    this.currentRankId,
    this.phone,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.emergencyContactEmail,
    this.photoUrl,
  });

  /// Serializes to the `{data: {...}}` envelope, omitting
  /// any null fields so a partial update only touches the
  /// supplied keys.
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (email != null) 'email': email,
      if (currentRankId != null)
        'current_rank_id': currentRankId,
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
      if (emergencyContactName != null)
        'emergency_contact_name': emergencyContactName,
      if (emergencyContactPhone != null)
        'emergency_contact_phone': emergencyContactPhone,
      if (emergencyContactEmail != null)
        'emergency_contact_email': emergencyContactEmail,
      if (photoUrl != null) 'photo_url': photoUrl,
    };
    return {'data': data};
  }

  @override
  List<Object?> get props => [
        firstName,
        lastName,
        email,
        currentRankId,
        phone,
        address,
        emergencyContactName,
        emergencyContactPhone,
        emergencyContactEmail,
        photoUrl,
      ];
}
