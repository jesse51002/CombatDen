import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_classes_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rank_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rewards_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_videos_slide.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// Assemble the showcase's slide list from what the kiosk already holds —
/// nothing here fetches; every argument is a gym-wide catalogue the flow cubit
/// warmed once at kiosk entry.
///
/// [classes] is `KioskFlowState.showcaseClasses`, the forward-looking list,
/// and never the check-in flow's `classes` — that one is per-member, narrowed
/// to the check-in window, and empty on the idle home and all evening.
///
/// **Every slide is conditional on real data, and its content is the gym's
/// own.** A slide whose list is empty is not added at all — no placeholder, no
/// stand-in, no demo content — because members read anything here as their
/// gym's actual schedule, catalogue, feed or belts. The rotating title, the
/// dots and the auto-rotate caption all derive from this list, so none of them
/// can advertise a missing slide either. The ONE exception is which rung
/// "Track rank" features and how full its bar sits (see `KioskRankSlide`); it
/// is not licence to invent content on the other three.
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
