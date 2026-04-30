import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/shared/widgets/topbar/gym_header.dart';
import 'package:mobile_app/shared/widgets/topbar/info_bar.dart';

class AppTopbar extends StatelessWidget {
  const AppTopbar({
    super.key,
    required this.gymName,
    required this.logoAsset,
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
  });

  final String gymName;
  final String logoAsset;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: DesignConstants.text3rd,
            width: DesignConstants.buttonBorder,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        top: DesignConstants.spacingBig,
        bottom: DesignConstants.spacingLarge,
        left: DesignConstants.spacingMedium,
        right: DesignConstants.spacingMedium,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          GymHeader(gymName: gymName, logoAsset: logoAsset),
          InfoBar(
            rankBadgeAsset: rankBadgeAsset,
            streakDays: streakDays,
            pointsLabel: pointsLabel,
          ),
        ],
      ),
    );
  }
}
