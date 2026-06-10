import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_value.dart';

part 'discount_update_request.g.dart';

/// Identity changes for `PUT /api/v1/discounts/` — renames the
/// gym_discounts row in place. Only non-null fields are sent.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  createFactory: false,
)
class DiscountUpdateIdentity {
  final String? discountName;

  const DiscountUpdateIdentity({this.discountName});

  Map<String, dynamic> toJson() =>
      _$DiscountUpdateIdentityToJson(this);
}

/// Body for `PUT /api/v1/discounts/` — identity keys plus the
/// destination sub-objects: [identity] (rename) and [value] (new
/// version). At least one must be present.
///
/// When [value] is provided the client MUST send the COMPLETE
/// [DiscountValue] spec (no partial merge with the current
/// version). Pre-fill all fields from the existing discount and
/// apply the user's edits on top.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class DiscountUpdateRequest {
  final String discountId;
  final String gymId;
  final DiscountUpdateIdentity? identity;
  final DiscountValue? value;

  const DiscountUpdateRequest({
    required this.discountId,
    required this.gymId,
    this.identity,
    this.value,
  });

  Map<String, dynamic> toJson() =>
      _$DiscountUpdateRequestToJson(this);
}
