import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_rewards_gate.dart';

/// The ORDER of the app-open celebration flow, as a single list — the one
/// place that decides which cards a member sees when they open the app.
///
/// Two independent things can be pending on one open, and the list composes
/// both:
///
/// * **Promotion** — card 0, gated on [rankEnabled] and [promoted] (the
///   promotion watermark's answer, decided once by `CelebrationDetector`). It
///   goes FIRST because a promotion is the reason to open the app, the `✕` is
///   live on every card so the biggest news must not be the reward for tapping
///   through three others, and — decisively — a belt card sitting immediately
///   after "you attended a class" would re-create by adjacency exactly the
///   class-caused-it reading the backend deliberately refused to encode.
/// * **The four CLASS cards**, gated as a group on [classAttended]. Without
///   that gate a promotion-only flow would chain into a streak card showing a
///   stale week and a points card showing **`+0 points`**, which is a false
///   statement about a class the member did not just attend. The wins recap is
///   in the group for the same reason: its tiles recap a class and its CTA is
///   "book your next class".
///
/// Inside the class group the two middle cards stay conditional on what the
/// gym actually runs, so a card is never shown for a feature the gym doesn't
/// have:
///
/// * **Rewards** — two independent gates, both of which must pass.
///   [hasRewards] asks whether the gym runs rewards at all (otherwise the card
///   would carousel the bundled demo catalog at a gym with none), and
///   [rewardsWorthShowing] asks whether THIS member can reach one: a card that
///   can only say "you can't have any of this" is worse than no card.
/// * **Rank** — only when the gym runs a rank ladder, the member holds a rank,
///   **and no promotion is being celebrated on this open**. The promotion card
///   just spent 2.6 seconds delivering the belt, and the rank card's own copy
///   is `{N} more classes until promotion` over a `classesSinceRank` the
///   promotion has just reset to 0 — it would read as "you have the furthest
///   still to go" thirty seconds after being told they arrived. One belt
///   moment per app open, composed out at the source.
///
/// **Wins is LAST in every flow that has a class.** It is the flow's closing
/// nudge: its CTA is the themed book-next-class slot rather than "Done", which
/// is why nothing after it would make sense. See `WinsScreen`.
///
/// The gym has no VIDEOS card in this flow (its only video card is the
/// post-BOOKING recommendation, gated separately on `gymHasVideos` by
/// `ClassBookedScreen`), so `gym_has_videos` does not appear here.
List<String> celebrationCardRoutes({
  required bool promoted,
  required bool classAttended,
  required bool hasRewards,
  required bool rewardsWorthShowing,
  required bool rankEnabled,
  required bool hasRank,
}) {
  return <String>[
    if (rankEnabled && promoted) AppRoutes.promotion,
    if (classAttended) ...[
      AppRoutes.postClassStreak,
      AppRoutes.postClassPoints,
      if (hasRewards && rewardsWorthShowing) AppRoutes.postClassRewards,
      if (rankEnabled && hasRank && !promoted) AppRoutes.postClassRank,
      AppRoutes.postClassWins,
    ],
  ];
}

/// The card AFTER [current] for the selected member's gym, or **null** when
/// [current] is the last one — which is what stops a card chaining into one
/// that was composed out, and lands the member home instead.
///
/// In a normally-composed class flow the only card that gets null back is
/// Wins, and Wins doesn't ask (it is unconditionally last and owns its own
/// CTA). The promotion card gets null back whenever no class is pending, which
/// is the common promotion-only shape — its CTA then reads "Done". Null also
/// reaches the other four through the PR-3 deep-link seam: a push can land on
/// a card this gym's flow skipped, and that card must end the flow rather than
/// guess a successor.
///
/// [data] is the route argument every card already holds; the two facts the
/// list needs come out of it — `promoted`, and `classAttended` as
/// `occurredAt != null`, which is already null on `CelebrationData.empty()`
/// and on a PR-3 deep link. [hasRank] and [pointsBalance] come from the live
/// profile (`MemberProfile.rank != null` / `retention.pointsBalance`); the gym
/// flags come from [selectedMember]; the reward costs come from the
/// [CelebrationRewardsGate] primed when the flow was pushed.
///
/// An UNDECIDED gate (still in flight, or its prime failed) reads as **show**,
/// per the app's default-to-show law. That can never flicker: once pushed,
/// `RewardsCardScreen` renders — it has no self-skip — so the worst case is a
/// card the member could have been spared, not one that appears and vanishes.
String? nextCelebrationCard({
  required String current,
  required CelebrationData data,
  required bool hasRank,
  required int? pointsBalance,
}) {
  final costs = CelebrationRewardsGate.instance.costs;
  final routes = celebrationCardRoutes(
    promoted: data.promoted,
    classAttended: data.occurredAt != null,
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

/// The CTA label for a card whose successor is [next]: a card that hands off
/// says "Continue", a card that ends the flow says "Done".
///
/// The Wins card is the ONE screen that doesn't call this — it closes every
/// class flow with the themed book-next-class label instead of "Done", because
/// the nudge to book again is the whole reason that card exists. "Done" is
/// reached by the promotion card whenever it is the only card pending, and by
/// any card left standing alone through the PR-3 deep-link seam.
String celebrationCtaLabel(String? next) => next == null ? 'Done' : 'Continue';
