// Hardcoded history data for the SpecificMember detail screen.
//
// These are the kinds of records the real API will eventually return
// from member-detail endpoints (rewards, stats, etc.). Field names are
// chosen to match the eventual API shape so the swap to repositories
// is mechanical.

/// A reward the member has redeemed in the gym's loyalty program.
class RedeemedReward {
  final String gymName;
  final String rewardName;
  final String costLabel;
  final String imageAsset;

  const RedeemedReward({
    required this.gymName,
    required this.rewardName,
    required this.costLabel,
    required this.imageAsset,
  });
}

/// Three recently-redeemed rewards used by the demo member.
const List<RedeemedReward> kMockRedeemedRewards = [
  RedeemedReward(
    gymName: 'Global MMA',
    rewardName: 'Bring a friend to a class',
    costLabel: 'Free',
    imageAsset: 'assets/images/reward_bring_friend.png',
  ),
  RedeemedReward(
    gymName: 'Global MMA',
    rewardName: 'Gym t-shirt',
    costLabel: 'Free',
    imageAsset: 'assets/images/reward_gym_tshirt.png',
  ),
  RedeemedReward(
    gymName: 'Global MMA',
    rewardName: 'Boxing gloves',
    costLabel: '10% off',
    imageAsset: 'assets/images/reward_boxing_gloves.png',
  ),
];

/// Aggregate counters surfaced under the rank/retention grids on the
/// SpecificMember screen. The real API will return one bundle per
/// member; today these are hardcoded for the demo.
class MemberDetailStats {
  final int classesInRank;
  final int classesUntilPromo;
  final int lastClassDaysAgo;
  final int pointsBalance;
  final int videosWatched;
  final int classStreakWeeks;

  const MemberDetailStats({
    required this.classesInRank,
    required this.classesUntilPromo,
    required this.lastClassDaysAgo,
    required this.pointsBalance,
    required this.videosWatched,
    required this.classStreakWeeks,
  });
}

const MemberDetailStats kMockMemberDetailStats = MemberDetailStats(
  classesInRank: 10,
  classesUntilPromo: 5,
  lastClassDaysAgo: 5,
  pointsBalance: 3400,
  videosWatched: 14,
  classStreakWeeks: 5,
);

/// The "demo" member shown on the SpecificMember screen. The Figma
/// frame shows Justin Stemmons specifically — he doesn't appear in
/// `kMockMembers` (which is the list-screen population), so he lives
/// here and is rendered standalone.
class DemoMember {
  final String fullName;
  final String statusLabel;
  final String email;
  final String rankLabel;
  final String rankIconAsset;

  const DemoMember({
    required this.fullName,
    required this.statusLabel,
    required this.email,
    required this.rankLabel,
    required this.rankIconAsset,
  });
}

const DemoMember kMockDemoMember = DemoMember(
  fullName: 'Justin Stemmons',
  statusLabel: 'Active',
  email: 'juston_stemmons@gmail.com',
  rankLabel: 'Silver (Amateur)',
  rankIconAsset: 'assets/images/rank_silver_belt.png',
);
