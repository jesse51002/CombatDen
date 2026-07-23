import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/features/videos/bloc/videos_bloc.dart';
import 'package:mobile_app/features/videos/bloc/videos_event.dart';
import 'package:mobile_app/features/videos/bloc/videos_state.dart';
import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';
import 'package:mobile_app/features/videos/data/repositories/member_videos_repository.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_category_tabs.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_body.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// The videos tab: the member's personalized gym feed from the portal. An "All"
/// tab plus one per genre present in the feed; selecting a genre reloads the
/// feed filtered server-side via `video_type`.
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
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.videos),
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

  void _onVideoTap(GymVideoCard card) => debugPrint('TODO: play ${card.url}');

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
            return _LoadedFeed(state: state, onVideoTap: _onVideoTap);
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
          onTabSelected: (index) => context
              .read<VideosBloc>()
              .add(VideosCategorySelected(tabGenres[index])),
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

class _Topbar extends StatelessWidget {
  const _Topbar();

  @override
  Widget build(BuildContext context) {
    return AppTopbar(
      mode: AppTopbarMode.nameOnly,
      showBackButton: false,
      gymName: selectedGym.displayName,
      logoAsset: mockGymGlobalMma.logoAsset,
      streakDays: mockGymGlobalMma.streakDays,
      pointsLabel: mockGymGlobalMma.pointsLabel,
      rankBadgeAsset: mockGymGlobalMma.rankBadgeAsset,
    );
  }
}
