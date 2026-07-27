import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';

/// The tab set for a gym with [hasRewards] / [hasVideos].
///
/// Home and Profile are STRUCTURAL — every gym has a schedule and every member
/// has a streak, so those two are always present. Rewards and Videos are
/// per-gym content: a gym with no active rewards, or whose feed would serve no
/// videos, gets no tab for them rather than a tab onto an empty screen.
///
/// Order is fixed (the enum's declaration order), so a tab never moves
/// position between two gyms that both have it.
List<AppBottomNavTab> navTabsFor({
  required bool hasRewards,
  required bool hasVideos,
}) {
  return <AppBottomNavTab>[
    for (final tab in AppBottomNavTab.values)
      if (switch (tab) {
        AppBottomNavTab.home => true,
        AppBottomNavTab.rank => true,
        AppBottomNavTab.reward => hasRewards,
        AppBottomNavTab.videos => hasVideos,
      })
        tab,
  ];
}

/// The tab set for the CURRENTLY selected member's gym. Every screen that
/// renders [AppBottomNavBar] passes this, so the tab set can't differ between
/// two tabs of the same app. Safe before a member is selected — the flags
/// default to true, i.e. the full set.
List<AppBottomNavTab> gymNavTabs() => navTabsFor(
      hasRewards: selectedMember.gymHasRewards,
      hasVideos: selectedMember.gymHasVideos,
    );
