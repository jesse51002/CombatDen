import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';
import 'package:mobile_app/shared/widgets/topbar/info_bar.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/gym_mark.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_back_button.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_frame.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_identity.dart';
import 'package:mobile_app/shared/widgets/topbar/topbar_data.dart';

/// `AppShellFormat.compactRail` — one row.
///
/// Mark leading, name centred, stats clustered trailing. Buys back the
/// vertical space the stacked mark spends, on every screen at once.
class TopbarCompactRail extends StatelessWidget {
  const TopbarCompactRail({super.key, required this.data});

  final TopbarData data;

  @override
  Widget build(BuildContext context) {
    return TopbarFrame(
      compact: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingMedium,
        children: [
          if (data.showBackButton) const TopbarBackButton(),
          Expanded(
            child: TopbarIdentity(
              data: data,
              markSize: data.mode == AppTopbarMode.bigLogo
                  ? GymMarkSize.sm
                  : null,
              axis: Axis.horizontal,
              nameStyle: DesignConstants.h2,
            ),
          ),
          InfoBar(
            rankBadgeAsset: data.rankBadgeAsset,
            streakDays: data.streakDays,
            pointsLabel: data.pointsLabel,
            layout: InfoBarLayout.cluster,
          ),
        ],
      ),
    );
  }
}
