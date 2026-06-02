import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/data/video_feed_repository.dart';
import 'package:mobile_app/features/videos/data/video_helpers.dart';
import 'package:mobile_app/features/videos/data/video_selectors.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_category_tabs.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_body.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// The top filters derive from the coarse `big_groups` the loaded feed
/// actually carries: an `All` tab plus one per distinct group. `null` scope =
/// the `All` filter.
class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key, this.captureController});

  /// Injected ONLY by the offline capture harness (`tools/capture/`) to drive a
  /// deterministic scroll for the landing-page theme reel. Null in normal app
  /// use, where the `SingleChildScrollView` owns its own implicit controller.
  final ScrollController? captureController;

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  final VideoFeedRepository _repository = VideoFeedRepository.instance;
  late final Future<List<Video>> _feed = _repository.feed();
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

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.videos),
      child: SingleChildScrollView(
        controller: widget.captureController,
        padding: EdgeInsets.only(bottom: DesignConstants.spacingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Topbar(),
            _Body(
              feed: _feed,
              selectedScope: _selectedScope,
              onScopeSelected: _onScopeSelected,
              onVideoTap: _openVideo,
            ),
          ],
        ),
      ),
    );
  }
}

/// The feed area below the topbar: builds the big-group tab strip from the
/// loaded feed, then the scoped hero + carousels. Tabs live here (not flush
/// under the topbar in the parent) because they derive from feed data.
class _Body extends StatelessWidget {
  const _Body({
    required this.feed,
    required this.selectedScope,
    required this.onScopeSelected,
    required this.onVideoTap,
  });

  final Future<List<Video>> feed;
  final String? selectedScope;
  final ValueChanged<String?> onScopeSelected;
  final ValueChanged<Video> onVideoTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Video>>(
      future: feed,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _FeedLoading();
        }
        if (snapshot.hasError) {
          return const _FeedMessage(text: 'Couldn\'t load videos right now.');
        }
        final videos = snapshot.data ?? const <Video>[];
        if (videos.isEmpty) {
          return const _FeedMessage(text: 'No videos yet.');
        }

        final scopes = bigGroupsInFeed(videos);
        final tabScopes = <String?>[null, ...scopes];
        final labels = ['All', ...scopes.map(displayLabel)];
        var selectedIndex = tabScopes.indexOf(selectedScope);
        if (selectedIndex < 0) selectedIndex = 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            VideoCategoryTabs(
              tabs: labels,
              selectedIndex: selectedIndex,
              onTabSelected: (index) => onScopeSelected(tabScopes[index]),
            ),
            VideosFeedBody(
              videos: videos,
              scope: tabScopes[selectedIndex],
              onVideoTap: onVideoTap,
            ),
          ],
        );
      },
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
