import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_classes_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rank_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rewards_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_videos_slide.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// Assemble the welcome showcase's slide list from whatever the kiosk already
/// holds in memory. Nothing here fetches — every argument is a gym-wide
/// catalogue the flow cubit warmed once at kiosk entry (rewards, videos, the
/// rank ladder), or the classes the flow already loaded for this member.
///
/// **Every slide is conditional on real data.** A slide whose list is empty is
/// not added at all — no placeholder, no stand-in, no demo content. The gym's
/// members would read anything on this screen as their gym's own schedule,
/// catalogue, feed or belts, so a slide the kiosk cannot back up simply does
/// not exist: the rotating title, the dots and the auto-rotate caption are all
/// derived from this list, so none of them can advertise a missing slide
/// either.
///
/// **The CONTENT of each slide is real too — with one deliberate exception.**
/// "Book classes" draws the real occurrences the flow loaded, "Earn rewards"
/// the gym's real cached catalogue, "Watch videos" the gym's own curated feed.
/// "Track rank" draws the gym's real ladder but features a MIDDLE rung over an
/// illustrative progress bar, on purpose — see `KioskRankSlide` for the
/// founder ruling behind it. Do not read that exception as licence to invent
/// content on the other three.
List<KioskShowcaseSlide> kioskShowcaseSlides({
  required List<EffectiveClassInstance> classes,
  required List<RewardResponse> rewards,
  required List<Video> videos,
  required List<KioskRankStep> rankLadder,
}) {
  return [
    if (classes.isNotEmpty)
      KioskShowcaseSlide(
        title: 'Book classes',
        body: KioskClassesSlide(classes: classes),
      ),
    if (rewards.isNotEmpty)
      KioskShowcaseSlide(
        title: 'Earn rewards',
        body: KioskRewardsSlide(rewards: rewards),
      ),
    if (videos.isNotEmpty)
      KioskShowcaseSlide(
        title: 'Watch videos',
        body: KioskVideosSlide(videos: videos),
      ),
    if (rankLadder.isNotEmpty)
      KioskShowcaseSlide(
        title: 'Track rank',
        body: KioskRankSlide(ladder: rankLadder),
      ),
  ];
}
