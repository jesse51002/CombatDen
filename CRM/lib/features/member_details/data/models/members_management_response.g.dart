// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'members_management_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MembersManagementResponse _$MembersManagementResponseFromJson(
  Map<String, dynamic> json,
) => MembersManagementResponse(
  memberId: json['member_id'] as String,
  gymId: json['gym_id'] as String,
  firstName: json['first_name'] as String,
  lastName: json['last_name'] as String,
  phone: json['phone'] as String?,
  email: json['email'] as String?,
  address: json['address'] as String?,
  emergencyContactName: json['emergency_contact_name'] as String?,
  emergencyContactPhone: json['emergency_contact_phone'] as String?,
  emergencyContactEmail: json['emergency_contact_email'] as String?,
  accountLinkedToId: json['account_linked_to_id'] as String?,
  stripeCustomerId: json['stripe_customer_id'] as String?,
  stripePaymentMethodId: json['stripe_payment_method_id'] as String?,
  cardBrand: json['card_brand'] as String?,
  cardLastFour: json['card_last_four'] as String?,
  cardExpMonth: (json['card_exp_month'] as num?)?.toInt(),
  cardExpYear: (json['card_exp_year'] as num?)?.toInt(),
);
