import 'package:json_annotation/json_annotation.dart';

part 'billing_personal_info.g.dart';

/// A member's personal information and emergency contact.
///
/// Mirrors `BillingPersonalInfo` in
/// `FastApiBackend/src/members/schema/members_billing_schema.py`.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class BillingPersonalInfo {
  final String? phone;
  final String? email;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? emergencyContactEmail;

  const BillingPersonalInfo({
    this.phone,
    this.email,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.emergencyContactEmail,
  });

  factory BillingPersonalInfo.fromJson(Map<String, dynamic> json) =>
      _$BillingPersonalInfoFromJson(json);
}
