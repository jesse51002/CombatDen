import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'reward_card_model.g.dart';

/// A recently redeemed reward.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class RewardCardModel extends Equatable {
  final String rewardId;
  final String title;
  final int pointCost;
  final String? priceLabel;
  final String? imageUrl;

  const RewardCardModel({
    required this.rewardId,
    required this.title,
    required this.pointCost,
    this.priceLabel,
    this.imageUrl,
  });

  factory RewardCardModel.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$RewardCardModelFromJson(json);

  @override
  List<Object?> get props => [
        rewardId,
        title,
        pointCost,
        priceLabel,
        imageUrl,
      ];
}
