// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'membership_plan_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MembershipPlanResponse _$MembershipPlanResponseFromJson(
  Map<String, dynamic> json,
) => MembershipPlanResponse(
  planId: json['plan_id'] as String,
  gymId: json['gym_id'] as String,
  planName: json['plan_name'] as String,
  imageUrl: json['image_url'] as String,
  planType: PlanType.fromJson(json['plan_type'] as String),
  classCount: (json['class_count'] as num?)?.toInt(),
  durationAmount: (json['duration_amount'] as num?)?.toInt(),
  durationUnit: MembershipPlanResponse._durationUnitFromJson(
    json['duration_unit'] as String?,
  ),
  isPublic: json['is_public'] as bool,
  stripeProductId: json['stripe_product_id'] as String?,
  createdAt: DateTime.parse(json['created_at'] as String),
  activePrice: json['active_price'] == null
      ? null
      : MembershipPlanPriceResponse.fromJson(
          json['active_price'] as Map<String, dynamic>,
        ),
  enrolledCount: (json['enrolled_count'] as num?)?.toInt() ?? 0,
  waiverIds:
      (json['waiver_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
);
