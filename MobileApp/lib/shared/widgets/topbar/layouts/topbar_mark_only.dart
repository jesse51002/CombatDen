import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/topbar/info_bar.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/gym_mark.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_back_button.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_frame.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_identity.dart';
import 'package:mobile_app/shared/widgets/topbar/topbar_data.dart';

/// `AppShellFormat.markOnly` — mark alone, stats inline, no rule.
///
/// The gym name is still built and still carries the switch-gym tap
/// target and its screen-reader label; it is only removed from the
/// visual layout. That is what keeps this a rearrangement rather than a
/// dropped affordance — see `GymNameLabel.visuallyHidden`.
class TopbarMarkOnly extends StatelessWidget {
  const TopbarMarkOnly({super.key, required this.data});

  final TopbarData data;

  @override
  Widget build(BuildContext context) {
    return TopbarFrame(
      rule: false,
      compact: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              TopbarIdentity(
                data: data,
                markSize: GymMarkSize.md,
                axis: Axis.horizontal,
                nameHidden: true,
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
          InfoBar(
            rankBadgeAsset: data.rankBadgeAsset,
            streakDays: data.streakDays,
            pointsLabel: data.pointsLabel,
            layout: InfoBarLayout.inline,
          ),
        ],
      ),
    );
  }
}
