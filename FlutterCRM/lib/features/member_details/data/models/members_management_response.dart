import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'members_management_response.g.dart';

/// Full member record returned by the members management
/// endpoints (update / update-card / link / unlink /
/// unlink-payment).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MembersManagementResponse extends Equatable {
  final String crmUserId;
  final String gymId;
  final String firstName;
  final String lastName;
  final String? phone;
  final String? email;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? emergencyContactEmail;
  final String? accountLinkedToId;
  final String? stripeCustomerId;
  final String? stripePaymentMethodId;
  final String? cardBrand;
  final String? cardLastFour;
  final int? cardExpMonth;
  final int? cardExpYear;

  const MembersManagementResponse({
    required this.crmUserId,
    required this.gymId,
    required this.firstName,
    required this.lastName,
    this.phone,
    this.email,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.emergencyContactEmail,
    this.accountLinkedToId,
    this.stripeCustomerId,
    this.stripePaymentMethodId,
    this.cardBrand,
    this.cardLastFour,
    this.cardExpMonth,
    this.cardExpYear,
  });

  factory MembersManagementResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MembersManagementResponseFromJson(json);

  @override
  List<Object?> get props => [
        crmUserId,
        gymId,
        firstName,
        lastName,
        phone,
        email,
        address,
        emergencyContactName,
        emergencyContactPhone,
        emergencyContactEmail,
        accountLinkedToId,
        stripeCustomerId,
        stripePaymentMethodId,
        cardBrand,
        cardLastFour,
        cardExpMonth,
        cardExpYear,
      ];
}
