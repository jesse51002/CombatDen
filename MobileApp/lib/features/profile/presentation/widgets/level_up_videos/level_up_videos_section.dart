import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/profile/presentation/widgets/level_up_videos/level_up_videos_header.dart';
import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';
import 'package:mobile_app/features/videos/data/repositories/member_videos_repository.dart';
import 'package:mobile_app/features/videos/presentation/widgets/gym_video_carousel_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_link_helpers.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';

// A small page of educational videos is plenty for the profile carousel.
const int _kLevelUpLimit = 10;

/// "Videos to level up" — a small page of the member's PORTAL feed filtered to
/// the Education genre, as a horizontal carousel on the profile page. Purely
/// supplementary: hidden until the feed loads, when the tenant has no
/// educational videos, and at a gym with no videos at all, so it never shows a
/// spinner or an error here — and never leaves a "View all" pointing at a tab
/// the gym doesn't have. NOT rank-dependent; it survives a rank-off gym.
/// Reuses the
/// videos feature's `GymVideoCard` model + `GymVideoCarouselCard`; tapping a
/// card opens it on YouTube through the same `openVideoFor` path as the videos
/// tab.
class LevelUpVideosSection extends StatefulWidget {
  const LevelUpVideosSection({super.key, this.leadingDivider = false});

  /// Draw a [SectionDivider] above the carousel — but only when the carousel
  /// itself renders. The rank-less profile has no rank block to separate it
  /// from, so it asks for its own rule; a stray divider over a self-hidden
  /// section would be a line under nothing.
  final bool leadingDivider;

  @override
  State<LevelUpVideosSection> createState() => _LevelUpVideosSectionState();
}

class _LevelUpVideosSectionState extends State<LevelUpVideosSection> {
  late final Future<List<GymVideoCard>> _future = _load();

  Future<List<GymVideoCard>> _load() async {
    final gymId = selectedMember.gymId;
    final memberId = selectedMember.memberId;
    if (gymId == null || memberId == null) return const [];
    // A gym whose feed serves nothing has no Videos tab either, so don't spend
    // a round trip to learn the carousel is empty — and don't leave its "View
    // all" as a surviving doorway into a tab that was hidden.
    if (!selectedMember.gymHasVideos) return const [];
    final feed = await MemberVideosRepository(apiClient: ApiClient()).fetchFeed(
      gymId: gymId,
      memberId: memberId,
      videoType: VideoGenre.educational,
      limit: _kLevelUpLimit,
    );
    return feed.videos;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GymVideoCard>>(
      future: _future,
      builder: (context, snapshot) {
        final ready =
            snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError;
        final videos =
            ready ? (snapshot.data ?? const <GymVideoCard>[]) : const [];
        if (videos.isEmpty) return const SizedBox.shrink();

        final carousel = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
              ),
              child: LevelUpVideosHeader(
                title: 'Videos to level up',
                onViewAll: () => Navigator.of(context).pushReplacementNamed(
                  AppRoutes.videos,
                  arguments: VideoGenre.educational.name,
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingLarge,
                children: [
                  for (final video in videos)
                    GymVideoCarouselCard(
                      card: video,
                      onTap: () => openVideoFor(context, video),
                    ),
                ],
              ),
            ),
          ],
        );

        if (!widget.leadingDivider) return carousel;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingBig,
          children: [const SectionDivider(), carousel],
        );
      },
    );
  }
}
