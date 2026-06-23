// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remove_authorization_preview.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RemoveAuthorizationMembership _$RemoveAuthorizationMembershipFromJson(
  Map<String, dynamic> json,
) => RemoveAuthorizationMembership(
  itemId: json['item_id'] as String,
  planName: json['plan_name'] as String,
  totalPrice: (json['total_price'] as num).toInt(),
);

RemoveAuthorizationPreview _$RemoveAuthorizationPreviewFromJson(
  Map<String, dynamic> json,
) => RemoveAuthorizationPreview(
  memberships:
      (json['memberships'] as List<dynamic>?)
          ?.map(
            (e) => RemoveAuthorizationMembership.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList() ??
      [],
  totalMonthly: (json['total_monthly'] as num?)?.toInt() ?? 0,
);
