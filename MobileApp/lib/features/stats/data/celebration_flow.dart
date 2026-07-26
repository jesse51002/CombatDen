import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/state/selected_member.dart';

/// The ORDER of the post-class celebration, as a single list — the one place
/// that decides which cards a member sees after a class.
///
/// Streak and Points are universal: every gym tracks attendance, and every
/// attended class is worth points. The other two are conditional on what the
/// gym actually runs, so a card is never shown for a feature the gym doesn't
/// have:
///
/// * **Rewards** — only when the gym has at least one active reward. Otherwise
///   the card would carousel the bundled demo catalog at a gym with none.
/// * **Rank** — only when the gym runs a rank ladder AND the member holds a
///   rank. A rank-enabled gym's ungraded member has no belt to celebrate yet.
///
/// The gym has no VIDEOS card in this flow (its only video card is the
/// post-BOOKING recommendation, gated separately on `gymHasVideos` by
/// `ClassBookedScreen`), so `gym_has_videos` does not appear here.
List<String> celebrationCardRoutes({
  required bool hasRewards,
  required bool rankEnabled,
  required bool hasRank,
}) {
  return <String>[
    AppRoutes.postClassStreak,
    AppRoutes.postClassPoints,
    if (hasRewards) AppRoutes.postClassRewards,
    if (rankEnabled && hasRank) AppRoutes.postClassRank,
  ];
}

/// The card AFTER [current] for the selected member's gym, or **null** when
/// [current] is the last one — which is what makes each card's CTA read "Done"
/// and land home instead of chaining into a card that was skipped.
///
/// [hasRank] comes from the live profile (`MemberProfile.rank != null`); the
/// gym flags come from [selectedMember].
String? nextCelebrationCard({
  required String current,
  required bool hasRank,
}) {
  final routes = celebrationCardRoutes(
    hasRewards: selectedMember.gymHasRewards,
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
