import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/core/utils/number_format.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/videos/bloc/videos_bloc.dart';
import 'package:mobile_app/features/videos/bloc/videos_event.dart';
import 'package:mobile_app/features/videos/bloc/videos_state.dart';
import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';
import 'package:mobile_app/features/videos/data/repositories/member_videos_repository.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_category_tabs.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_link_helpers.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_body.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/nav/nav_tabs.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// The videos tab: the member's personalized gym feed from the portal — a
/// featured hero plus one carousel per genre present in the feed.
///
/// The tab row is genre NAVIGATION, not a filter: "All" is this screen, and a
/// genre tab opens that genre's full list (`TagVideosScreen`), the same
/// destination as the matching carousel's "View all".
class VideosScreen extends StatelessWidget {
  const VideosScreen({super.key, this.captureController});

  /// Injected ONLY by the offline capture harness (`tools/capture/`) to drive a
  /// deterministic scroll for the landing-page theme reel. Null in normal app
  /// use, where the `SingleChildScrollView` owns its own implicit controller.
  final ScrollController? captureController;

  @override
  Widget build(BuildContext context) {
    // Honor an initial category passed by a deep link (e.g. the profile's
    // "videos to level up" → 'educational'). Resilient-parsed; a non-genre arg
    // opens on "All".
    final arg = ModalRoute.of(context)?.settings.arguments;
    final initialGenre =
        arg is String ? videoGenreOrNullFromJson(arg) : null;

    return BlocProvider<VideosBloc>(
      create: (_) => VideosBloc(
        repository: MemberVideosRepository(apiClient: ApiClient()),
      )..add(VideosLoadRequested(initialGenre: initialGenre)),
      child: _VideosScaffold(captureController: captureController),
    );
  }
}

class _VideosScaffold extends StatelessWidget {
  const _VideosScaffold({this.captureController});

  final ScrollController? captureController;

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: AppBottomNavBar(
        selected: AppBottomNavTab.videos,
        tabs: gymNavTabs(),
      ),
      child: SingleChildScrollView(
        controller: captureController,
        padding: EdgeInsets.only(bottom: DesignConstants.spacingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            _Topbar(),
            _Body(),
          ],
        ),
      ),
    );
  }
}

/// The feed area below the topbar: the genre tab strip, then the scoped hero +
/// carousels — with loading / empty / retryable-error states.
class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VideosBloc, VideosState>(
      builder: (context, state) {
        switch (state.status) {
          case VideosStatus.initial:
          case VideosStatus.loading:
            return const _FeedLoading();
          case VideosStatus.error:
            return _FeedError(
              message: state.errorMessage ?? 'Couldn\'t load videos right now.',
              onRetry: () => context
                  .read<VideosBloc>()
                  .add(const VideosLoadRequested()),
            );
          case VideosStatus.loaded:
            if (state.videos.isEmpty && state.availableGenres.isEmpty) {
              return const _FeedMessage(text: 'No videos yet.');
            }
            // A video plays on YouTube, outside the app — there is no in-app
            // player.
            return _LoadedFeed(
              state: state,
              onVideoTap: (card) => openVideoFor(context, card),
            );
        }
      },
    );
  }
}

class _LoadedFeed extends StatelessWidget {
  const _LoadedFeed({required this.state, required this.onVideoTap});

  final VideosState state;
  final ValueChanged<GymVideoCard> onVideoTap;

  @override
  Widget build(BuildContext context) {
    final genres = state.availableGenres;
    final tabGenres = <VideoGenre?>[null, ...genres];
    final labels = ['All', ...genres.map((g) => g.label)];
    var selectedIndex = tabGenres.indexOf(state.selectedGenre);
    if (selectedIndex < 0) selectedIndex = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        VideoCategoryTabs(
          tabs: labels,
          selectedIndex: selectedIndex,
          // A genre tab OPENS that genre's full list; it does not re-filter
          // this screen. Filtering in place kept the hero-plus-carousel
          // layout, so picking one genre showed a big featured video above a
          // single carousel of the same genre — the hero and the "view all"
          // carousel were then two routes to the same handful of videos.
          // `TagVideosScreen` is already the right shape for one genre (a
          // flat list), and is what each carousel's "View all" opens, so a
          // tab and a "View all" now land in the same place.
          onTabSelected: (index) {
            final genre = tabGenres[index];
            if (genre == null) {
              context
                  .read<VideosBloc>()
                  .add(const VideosCategorySelected(null));
              return;
            }
            Navigator.of(context).pushNamed(
              AppRoutes.videoTagList,
              arguments: genre,
            );
          },
        ),
        VideosFeedBody(videos: state.videos, onVideoTap: onVideoTap),
      ],
    );
  }
}

class _FeedLoading extends StatelessWidget {
  const _FeedLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _FeedMessage extends StatelessWidget {
  const _FeedMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
      ),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
      child: Column(
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text('Retry', style: DesignConstants.p),
          ),
        ],
      ),
    );
  }
}

// Bundled fallback assets for the topbar's theme-driven logo / rank belt.
const String _kDefaultLogoAsset = 'gym_logo_global_mma.png';
const String _kDefaultRankBadgeAsset = 'icon_rank_belt.png';

/// The videos tab's name-only topbar: gym name from the selected member, and
/// streak / points read LIVE from the shared [MemberProfileBloc] — the same
/// per-member chrome the home and rewards topbars render, never mock.
class _Topbar extends StatelessWidget {
  const _Topbar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      builder: (context, state) {
        final retention = state.profile?.retention;
        return AppTopbar(
          mode: AppTopbarMode.nameOnly,
          showBackButton: false,
          gymName: selectedMember.gymName ?? '',
          memberName: selectedMember.fullName,
          memberPhotoUrl: selectedMember.photoUrl,
          memberFirstName: selectedMember.firstName,
          memberLastName: selectedMember.lastName,
          logoAsset: _kDefaultLogoAsset,
          gymLogoUrl: selectedMember.gymLogoUrl,
          streakDays: retention?.classStreakWeeks ?? 0,
          pointsLabel:
              retention != null ? formatCount(retention.pointsBalance) : '—',
          rankBadgeAsset: _kDefaultRankBadgeAsset,
          rankImageUrl: state.profile?.rank?.imageUrl,
          showRank: selectedMember.gymRankEnabled,
          pointsSpendable: selectedMember.gymHasRewards,
          onTitleDoubleTap: () =>
              Navigator.of(context).pushNamed(AppRoutes.memberSelect),
        );
      },
    );
  }
}
