import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/line_item_type.dart';

part 'line_item_record.g.dart';

/// A single line item on an invoice.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class LineItemRecord extends Equatable {
  final String lineItemId;
  @JsonKey(fromJson: LineItemType.fromJson)
  final LineItemType itemType;
  final String name;
  final int amount;
  @JsonKey(defaultValue: 1)
  final int quantity;
  final String? stripeProductId;
  final String? itemId;

  /// The member this line was FOR (a membership line resolves its owner;
  /// a custom/ad-hoc line has none) — lets the UI label "Plan · Owner".
  final String? ownerMemberId;
  final String? ownerFirstName;
  final String? ownerLastName;

  const LineItemRecord({
    required this.lineItemId,
    required this.itemType,
    required this.name,
    required this.amount,
    this.quantity = 1,
    this.stripeProductId,
    this.itemId,
    this.ownerMemberId,
    this.ownerFirstName,
    this.ownerLastName,
  });

  /// The owner's display name, or '' when this line has no owner.
  String get ownerName =>
      '${ownerFirstName ?? ''} ${ownerLastName ?? ''}'.trim();

  factory LineItemRecord.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$LineItemRecordFromJson(json);

  @override
  List<Object?> get props => [
        lineItemId,
        itemType,
        name,
        amount,
        quantity,
        stripeProductId,
        itemId,
        ownerMemberId,
        ownerFirstName,
        ownerLastName,
      ];
}
