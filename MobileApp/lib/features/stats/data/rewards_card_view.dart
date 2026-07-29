import 'dart:math' as math;

// The ONE public points formatter (thousand separators). It is a pure
// function, not a widget — the reward-card file is simply where it lives
// today; promoting it to a shared helper is tracked separately.
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card.dart'
    show formatRewardPoints;
import 'package:mobile_app/features/stats/data/reward_slide.dart';

/// What a member can do with one reward RIGHT NOW.
///
/// [unknown] is not a third affordability tier — it is "we can't say": the
/// shared profile hasn't landed (or errored), or the slide is a bundled
/// fallback whose cost is a demo number. It renders exactly as the card
/// shipped before affordability existed.
enum RewardAffordance { redeemable, locked, unknown }

/// One carousel slide with its affordability resolved.
class RewardsCardSlide {
  const RewardsCardSlide({
    required this.slide,
    required this.affordance,
    required this.progress,
    required this.valueLabel,
  });

  final RewardSlide slide;
  final RewardAffordance affordance;

  /// How much of the frame's ring is drawn, 0..1. Always 1.0 for a redeemable
  /// or unknown slide — both close the ring.
  final double progress;

  /// `'800 pts'` when the member can have it (or we can't say), the
  /// `'120 / 2,200 points'` progress sentence when they can't.
  final String valueLabel;
}

/// Everything the rewards card renders, decided in one place so no widget
/// re-derives a state.
class RewardsCardView {
  const RewardsCardView({
    required this.title,
    required this.subtitle,
    required this.featuredIndex,
    required this.slides,
  });

  final String title;
  final String subtitle;
  final int featuredIndex;
  final List<RewardsCardSlide> slides;
}

/// Resolve every slide's affordance against [pointsBalance], then derive the
/// card's title, subtitle and opening slide from the result.
///
/// A null [pointsBalance] is UNKNOWN, never zero: the profile is null while it
/// loads and after an error with no last-good value, and rendering
/// `0 / 2,200 points` would be a false statement about a member who may have
/// 3,000 points.
RewardsCardView buildRewardsCardView({
  required List<RewardSlide> slides,
  required int? pointsBalance,
}) {
  final resolved = <RewardsCardSlide>[
    for (final slide in slides) _resolve(slide, pointsBalance),
  ];
  return RewardsCardView(
    title: _title(resolved),
    subtitle: _subtitle(resolved, pointsBalance),
    featuredIndex: _featuredIndex(resolved),
    slides: resolved,
  );
}

RewardsCardSlide _resolve(RewardSlide slide, int? balance) {
  final cost = slide.pointsCost;
  final priced = '${formatRewardPoints(cost)} pts';
  if (!slide.isLive || balance == null) {
    return RewardsCardSlide(
      slide: slide,
      affordance: RewardAffordance.unknown,
      progress: 1,
      valueLabel: priced,
    );
  }
  if (cost <= 0 || cost <= balance) {
    return RewardsCardSlide(
      slide: slide,
      affordance: RewardAffordance.redeemable,
      progress: 1,
      valueLabel: priced,
    );
  }
  return RewardsCardSlide(
    slide: slide,
    affordance: RewardAffordance.locked,
    progress: (balance / cost).clamp(0.0, 1.0),
    valueLabel:
        '${formatRewardPoints(balance)} / ${formatRewardPoints(cost)} points',
  );
}

String _title(List<RewardsCardSlide> slides) =>
    _lockedOnly(slides) ? 'Almost there' : 'Rewards you can get';

String _subtitle(List<RewardsCardSlide> slides, int? balance) {
  final ready = slides.where(_isRedeemable).length;
  if (ready > 0) {
    return ready == 1
        ? '1 reward ready to redeem'
        : '$ready rewards ready to redeem';
  }
  if (_lockedOnly(slides) && balance != null) {
    final cheapest =
        slides.map((s) => s.slide.pointsCost).reduce(math.min);
    return '${formatRewardPoints(cheapest - balance)} points to go';
  }
  return 'Swipe to view rewards';
}

/// The opening slide: the biggest thing the member can have right now, or —
/// when nothing is affordable — the cheapest one, which is what the "almost
/// there" claim is about. The catalog arrives cheapest-first
/// (`list_rewards.sql` ends `ORDER BY point_cost ASC`), so index 0 IS the
/// cheapest; the card-level maths below never assumes it.
int _featuredIndex(List<RewardsCardSlide> slides) {
  var best = -1;
  var bestCost = -1;
  for (var i = 0; i < slides.length; i++) {
    if (!_isRedeemable(slides[i])) continue;
    final cost = slides[i].slide.pointsCost;
    if (best < 0 || cost > bestCost) {
      best = i;
      bestCost = cost;
    }
  }
  return best < 0 ? 0 : best;
}

bool _isRedeemable(RewardsCardSlide s) =>
    s.affordance == RewardAffordance.redeemable;

/// True when every slide is locked — the "almost there" state. An empty list
/// and any unknown slide both fall through to the neutral copy.
bool _lockedOnly(List<RewardsCardSlide> slides) =>
    slides.isNotEmpty &&
    slides.every((s) => s.affordance == RewardAffordance.locked);
