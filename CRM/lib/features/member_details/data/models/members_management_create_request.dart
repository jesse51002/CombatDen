import 'package:equatable/equatable.dart';

/// Body for `POST /api/v1/members/` — create a member shell.
///
/// Mirrors the backend `MemberCreateRequest` (a FLAT body, snake_case).
/// [gymId], [firstName], [lastName] are required; the rest are optional
/// contact / profile columns, omitted from the JSON when null so the backend
/// applies its own defaults. [allowDuplicate] is always sent: false gates the
/// create against a same-identity duplicate (409), true confirms and creates
/// anyway.
///
/// Hand-written `toJson` (not `json_serializable`) because the class extends
/// [Equatable]: the generator would otherwise serialize Equatable's `props` /
/// `hashCode` / `stringify` getters into the body. Mirrors the sibling
/// `MembersManagementUpdateRequest`.
class MembersManagementCreateRequest extends Equatable {
  final String gymId;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? emergencyContactEmail;
  final String? photoUrl;
  final String? currentRankId;
  final String? userId;
  final String? paymentMethodId;
  final bool allowDuplicate;

  const MembersManagementCreateRequest({
    required this.gymId,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.emergencyContactEmail,
    this.photoUrl,
    this.currentRankId,
    this.userId,
    this.paymentMethodId,
    this.allowDuplicate = false,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'gym_id': gymId,
      'first_name': firstName,
      'last_name': lastName,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
      if (emergencyContactName != null)
        'emergency_contact_name': emergencyContactName,
      if (emergencyContactPhone != null)
        'emergency_contact_phone': emergencyContactPhone,
      if (emergencyContactEmail != null)
        'emergency_contact_email': emergencyContactEmail,
      if (photoUrl != null) 'photo_url': photoUrl,
      if (currentRankId != null) 'current_rank_id': currentRankId,
      if (userId != null) 'user_id': userId,
      if (paymentMethodId != null)
        'payment_method_id': paymentMethodId,
      'allow_duplicate': allowDuplicate,
    };
  }

  /// The same request re-sent to confirm a duplicate create.
  MembersManagementCreateRequest copyWith({
    bool? allowDuplicate,
  }) {
    return MembersManagementCreateRequest(
      gymId: gymId,
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
      address: address,
      emergencyContactName: emergencyContactName,
      emergencyContactPhone: emergencyContactPhone,
      emergencyContactEmail: emergencyContactEmail,
      photoUrl: photoUrl,
      currentRankId: currentRankId,
      userId: userId,
      paymentMethodId: paymentMethodId,
      allowDuplicate: allowDuplicate ?? this.allowDuplicate,
    );
  }

  @override
  List<Object?> get props => [
        gymId,
        firstName,
        lastName,
        email,
        phone,
        address,
        emergencyContactName,
        emergencyContactPhone,
        emergencyContactEmail,
        photoUrl,
        currentRankId,
        userId,
        paymentMethodId,
        allowDuplicate,
      ];
}
