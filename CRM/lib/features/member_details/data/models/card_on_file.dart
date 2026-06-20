import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'card_on_file.g.dart';

/// The member's OWN saved card, surfaced once at the response
/// root rather than per membership.
///
/// Mirrors the merged `BillingCardOnFile` schema. Per-payer
/// billing: this is the queried member's own card (their Stripe
/// customer's default), never a linked parent's — so a
/// payer-scoped read (the charge dialog / start wizard fetching
/// the chosen payer's billing) shows the card that will actually
/// be charged. Null when the member has no saved card of their own.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class CardOnFile extends Equatable {
  final String brand;
  final String lastFour;
  final int expMonth;
  final int expYear;

  const CardOnFile({
    required this.brand,
    required this.lastFour,
    required this.expMonth,
    required this.expYear,
  });

  factory CardOnFile.fromJson(Map<String, dynamic> json) =>
      _$CardOnFileFromJson(json);

  @override
  List<Object?> get props => [
        brand,
        lastFour,
        expMonth,
        expYear,
      ];
}
