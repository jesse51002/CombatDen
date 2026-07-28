import 'package:mobile_app/features/profile/data/mock_profile.dart';

/// Everything a rank layout may render, gathered once.
///
/// Every layout receives the SAME payload and must render every element
/// in it: the topbar, the streak hero, the current rank, the rating
/// graph with its range selector, all four next-rank elements, and the
/// level-up videos. A layout may move them and change their prominence.
/// It may not drop one, add one, or reach for anything not in here —
/// which is what keeps the enum a choice of ARRANGEMENT.
///
/// Note what is deliberately absent: any notion of rank HISTORY. The
/// screen fetches the current rank and the next one, and nothing else,
/// so no arrangement can imply a progression it cannot show.
class RankLayoutData {
  const RankLayoutData({
    required this.profile,
    required this.gymName,
    required this.logoAsset,
  });

  final MockProfile profile;
  final String gymName;
  final String logoAsset;
}
