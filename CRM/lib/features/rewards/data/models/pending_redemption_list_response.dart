import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/rewards/data/models/pending_redemption_item.dart';

part 'pending_redemption_list_response.g.dart';

/// The gym-wide pending redemption queue (paginated).
/// Mirrors `PendingRedemptionListResponse` from
/// `FastApiBackend/src/rewards/schema/rewards_schema.py`.
///
/// The CRM only fetches the default first page; [total] is the full
/// server-side count (a load-more UI is out of scope for now).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class PendingRedemptionListResponse {
  final List<PendingRedemptionItem> items;
  final int total;

  const PendingRedemptionListResponse({
    required this.items,
    required this.total,
  });

  factory PendingRedemptionListResponse.fromJson(Map<String, dynamic> json) =>
      _$PendingRedemptionListResponseFromJson(json);
}
