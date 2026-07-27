import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/stats/data/celebration_rewards_gate.dart';

/// The ORDER of the post-class celebration, as a single list — the one place
/// that decides which cards a member sees after a class.
///
/// Streak and Points are universal: every gym tracks attendance, and every
/// attended class is worth points. The other two are conditional on what the
/// gym actually runs, so a card is never shown for a feature the gym doesn't
/// have:
///
/// * **Rewards** — two independent gates, both of which must pass.
///   [hasRewards] asks whether the gym runs rewards at all (otherwise the card
///   would carousel the bundled demo catalog at a gym with none), and
///   [rewardsWorthShowing] asks whether THIS member can reach one: a card that
///   can only say "you can't have any of this" is worse than no card.
/// * **Rank** — only when the gym runs a rank ladder AND the member holds a
///   rank. A rank-enabled gym's ungraded member has no belt to celebrate yet.
///
/// The gym has no VIDEOS card in this flow (its only video card is the
/// post-BOOKING recommendation, gated separately on `gymHasVideos` by
/// `ClassBookedScreen`), so `gym_has_videos` does not appear here.
List<String> celebrationCardRoutes({
  required bool hasRewards,
  required bool rewardsWorthShowing,
  required bool rankEnabled,
  required bool hasRank,
}) {
  return <String>[
    AppRoutes.postClassStreak,
    AppRoutes.postClassPoints,
    if (hasRewards && rewardsWorthShowing) AppRoutes.postClassRewards,
    if (rankEnabled && hasRank) AppRoutes.postClassRank,
  ];
}

/// The card AFTER [current] for the selected member's gym, or **null** when
/// [current] is the last one — which is what makes each card's CTA read "Done"
/// and land home instead of chaining into a card that was skipped.
///
/// [hasRank] and [pointsBalance] come from the live profile
/// (`MemberProfile.rank != null` / `retention.pointsBalance`); the gym flags
/// come from [selectedMember]; the reward costs come from the
/// [CelebrationRewardsGate] primed when the flow was pushed.
///
/// An UNDECIDED gate (still in flight, or its prime failed) reads as **show**,
/// per the app's default-to-show law. That can never flicker: once pushed,
/// `RewardsCardScreen` renders — it has no self-skip — so the worst case is a
/// card the member could have been spared, not one that appears and vanishes.
String? nextCelebrationCard({
  required String current,
  required bool hasRank,
  required int? pointsBalance,
}) {
  final costs = CelebrationRewardsGate.instance.costs;
  final routes = celebrationCardRoutes(
    hasRewards: selectedMember.gymHasRewards,
    rewardsWorthShowing: costs == null
        ? true
        : rewardsCardWorthShowing(balance: pointsBalance, costs: costs),
    rankEnabled: selectedMember.gymRankEnabled,
    hasRank: hasRank,
  );
  final index = routes.indexOf(current);
  if (index < 0 || index + 1 >= routes.length) return null;
  return routes[index + 1];
}

/// The CTA label for a card whose successor is [next]: the LAST card says
/// "Done", every other one says "Continue".
String celebrationCtaLabel(String? next) => next == null ? 'Done' : 'Continue';
