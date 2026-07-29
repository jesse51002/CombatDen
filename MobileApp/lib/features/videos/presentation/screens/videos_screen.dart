import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/data/video_feed_repository.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_layout_data.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_body.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_status.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// The top filters derive from the coarse `big_groups` the loaded feed
/// actually carries: an `All` tab plus one per distinct group. `null` scope =
/// the `All` filter.
class VideosScreen extends StatefulWidget {
  const VideosScreen({
    super.key,
    this.captureController,
    this.feedOverride,
    this.formatOverride,
  });

  /// Injected ONLY by the offline capture harness (`tools/capture/`) to drive a
  /// deterministic scroll for the landing-page theme reel. Null in normal app
  /// use, where the `CustomScrollView` owns its own implicit controller.
  final ScrollController? captureController;

  /// Stands in for the repository fetch so the screen can be rendered
  /// without a backend. Used by the layout-invariant tests and the
  /// format preview; null in normal app use.
  final Future<List<Video>>? feedOverride;

  /// Forces a layout instead of resolving it from the customization.
  /// Tests and the format preview only; null in normal app use.
  final VideosFormat? formatOverride;

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  final VideoFeedRepository _repository = VideoFeedRepository.instance;
  late final Future<List<Video>> _feed =
      widget.feedOverride ?? _repository.feed();
  String? _selectedScope;
  bool _appliedInitialFilter = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honor an initial filter passed by the caller (e.g. the rank page's
    // "view all" opens straight to 'educational'). Applied once so later taps
    // aren't overridden.
    if (_appliedInitialFilter) return;
    _appliedInitialFilter = true;
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String) _selectedScope = arg;
  }

  void _onScopeSelected(String? scope) {
    if (scope == _selectedScope) return;
    setState(() => _selectedScope = scope);
  }

  // Real playback (opening the YouTube url) is a follow-up; no-op for now.
  void _openVideo(Video video) => debugPrint('TODO: play ${video.url}');

  void _openTag(String tag) => Navigator.of(context).pushNamed(
    AppRoutes.videoTagList,
    arguments: tag,
  );

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.videos),
      child: CustomScrollView(
        controller: widget.captureController,
        slivers: [
          const SliverToBoxAdapter(child: _Topbar()),
          SliverPadding(
            padding: EdgeInsets.only(bottom: DesignConstants.spacingBig),
            sliver: _Feed(
              feed: _feed,
              selectedScope: _selectedScope,
              onScopeSelected: _onScopeSelected,
              onVideoTap: _openVideo,
              onViewAll: _openTag,
              formatOverride: widget.formatOverride,
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolves the feed request, then hands the loaded videos to whichever
/// layout the tenant's `videos_format` selects. Loading, error and an
/// empty gym stay here: they are the same in every layout, because a
/// format arranges videos and there are none to arrange.
class _Feed extends StatelessWidget {
  const _Feed({
    required this.feed,
    required this.selectedScope,
    required this.onScopeSelected,
    required this.onVideoTap,
    required this.onViewAll,
    this.formatOverride,
  });

  final Future<List<Video>> feed;
  final String? selectedScope;
  final ValueChanged<String?> onScopeSelected;
  final ValueChanged<Video> onVideoTap;
  final ValueChanged<String> onViewAll;
  final VideosFormat? formatOverride;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Video>>(
      future: feed,
      builder: (context, snapshot) {
        final videos = snapshot.data ?? const <Video>[];
        final status = switch (snapshot) {
          _ when snapshot.connectionState != ConnectionState.done =>
            VideosFeedStatusKind.loading,
          _ when snapshot.hasError => VideosFeedStatusKind.error,
          _ when videos.isEmpty => VideosFeedStatusKind.empty,
          _ => null,
        };
        if (status != null) {
          return SliverToBoxAdapter(child: VideosFeedStatus(kind: status));
        }

        return VideosFeedBody(
          formatOverride: formatOverride,
          data: VideosLayoutData.fromFeed(
            videos: videos,
            scope: selectedScope,
            onScopeSelected: onScopeSelected,
            onVideoTap: onVideoTap,
            onViewAll: onViewAll,
          ),
        );
      },
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
