import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';
import 'package:mobile_app/shared/widgets/topbar/info_bar.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/gym_mark.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_back_button.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_frame.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_identity.dart';
import 'package:mobile_app/shared/widgets/topbar/topbar_data.dart';

/// `AppShellFormat.stacked` — the arrangement that ships today.
///
/// Big square mark above the gym name (home only, via
/// `AppTopbarMode.bigLogo`), stats spread across a full-width bar
/// beneath. This layout reproduces the previous `AppTopbar` rendering
/// value for value, so a tenant with no layout slot sees no change.
class TopbarStacked extends StatelessWidget {
  const TopbarStacked({super.key, required this.data});

  final TopbarData data;

  @override
  Widget build(BuildContext context) {
    final bigLogo = data.mode == AppTopbarMode.bigLogo;
    return TopbarFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              TopbarIdentity(
                data: data,
                markSize: bigLogo ? GymMarkSize.lg : null,
                axis: Axis.vertical,
                nameStyle: bigLogo
                    ? DesignConstants.h1
                    : DesignConstants.h2,
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
          ),
        ],
      ),
    );
  }
}
