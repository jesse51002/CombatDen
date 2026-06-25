import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'members_management_response.g.dart';

/// Member billing profile returned by the billing
/// management endpoints (update-card / link / unlink /
/// unlink-payment).
///
/// Mirrors the merged `MembersBillingProfileResponse`
/// schema (member-id keyed). The class name is kept from
/// the pre-merge codebase so the repository / bloc
/// contract is stable.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MembersManagementResponse extends Equatable {
  final String memberId;
  final String gymId;
  final String firstName;
  final String lastName;
  final String? phone;
  final String? email;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? emergencyContactEmail;
  final String? stripeCustomerId;
  final String? stripePaymentMethodId;
  final String? cardBrand;
  final String? cardLastFour;
  final int? cardExpMonth;
  final int? cardExpYear;

  const MembersManagementResponse({
    required this.memberId,
    required this.gymId,
    required this.firstName,
    required this.lastName,
    this.phone,
    this.email,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.emergencyContactEmail,
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
        memberId,
        gymId,
        firstName,
        lastName,
        phone,
        email,
        address,
        emergencyContactName,
        emergencyContactPhone,
        emergencyContactEmail,
        stripeCustomerId,
        stripePaymentMethodId,
        cardBrand,
        cardLastFour,
        cardExpMonth,
        cardExpYear,
      ];
}
