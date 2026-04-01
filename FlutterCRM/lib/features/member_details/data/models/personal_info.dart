import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'personal_info.g.dart';

/// Member personal information and emergency contact.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PersonalInfo extends Equatable {
  final String? phone;
  final String? email;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? emergencyContactEmail;
  final String? waiverId;

  const PersonalInfo({
    this.phone,
    this.email,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.emergencyContactEmail,
    this.waiverId,
  });

  factory PersonalInfo.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$PersonalInfoFromJson(json);

  @override
  List<Object?> get props => [
        phone,
        email,
        address,
        emergencyContactName,
        emergencyContactPhone,
        emergencyContactEmail,
        waiverId,
      ];
}
