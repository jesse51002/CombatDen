import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';
import 'package:mobile_app/shared/widgets/topbar/info_bar.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/gym_mark.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_back_button.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_frame.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_identity.dart';
import 'package:mobile_app/shared/widgets/topbar/topbar_data.dart';

/// `AppShellFormat.statFirst` — stats above identity.
///
/// For a tenant whose retention story is the numbers rather than the
/// brand mark. Identity drops to a small centred row beneath.
class TopbarStatFirst extends StatelessWidget {
  const TopbarStatFirst({super.key, required this.data});

  final TopbarData data;

  @override
  Widget build(BuildContext context) {
    return TopbarFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          InfoBar(
            rankBadgeAsset: data.rankBadgeAsset,
            streakDays: data.streakDays,
            pointsLabel: data.pointsLabel,
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              TopbarIdentity(
                data: data,
                markSize: data.mode == AppTopbarMode.bigLogo
                    ? GymMarkSize.xs
                    : null,
                axis: Axis.horizontal,
                nameStyle: DesignConstants.p,
              ),
              if (data.showBackButton)
                const Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TopbarBackButton(),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
