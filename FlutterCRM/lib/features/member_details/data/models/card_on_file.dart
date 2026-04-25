import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'card_on_file.g.dart';

/// Saved card details for the paying account.
///
/// Only the parent account in a linked family can hold a
/// card (enforced by the `linked_account_no_stripe` check
/// constraint in the database), so these fields are
/// surfaced once at the response root rather than per
/// membership.
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
