import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The brand-coloured price chip a reward carries ("Free", "30% off").
///
/// Exactly one per reward card in every layout. Where it SITS changes
/// (over the image corner, or inline beside the title); that it exists
/// does not.
class RewardPriceTag extends StatelessWidget {
  const RewardPriceTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brand = DesignConstants.primaryColor;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        color: brand,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.primaryButtonText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
