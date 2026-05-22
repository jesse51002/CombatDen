import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/data/video_feed_repository.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_category_tabs.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_body.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// The top filters map onto the server's coarse `big_groups`: All (no
/// filter), Education, Entertainment.
const List<String> _kTopFilters = ['All', 'Education', 'Entertainment'];

BigGroup? _scopeForTab(int index) => switch (index) {
  1 => BigGroup.educational,
  2 => BigGroup.entertainment,
  _ => null,
};

int _tabForScope(BigGroup scope) => switch (scope) {
  BigGroup.educational => 1,
  BigGroup.entertainment => 2,
  _ => 0,
};

class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  final VideoFeedRepository _repository = VideoFeedRepository.instance;
  late final Future<List<Video>> _feed = _repository.feed();
  int _selectedTab = 0;
  bool _appliedInitialFilter = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honor an initial filter passed by the caller (e.g. the rank page's
    // "view all" opens straight to Education). Applied once so later taps
    // aren't overridden.
    if (_appliedInitialFilter) return;
    _appliedInitialFilter = true;
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is BigGroup) _selectedTab = _tabForScope(arg);
  }

  void _onTabSelected(int index) {
    if (index == _selectedTab) return;
    setState(() => _selectedTab = index);
  }

  // Real playback (opening the YouTube url) is a follow-up; no-op for now.
  void _openVideo(Video video) => debugPrint('TODO: play ${video.url}');

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.videos),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: DesignConstants.spacingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            _Header(
              tabs: _kTopFilters,
              selectedIndex: _selectedTab,
              onTabSelected: _onTabSelected,
            ),
            _FeedSection(
              repository: _repository,
              feed: _feed,
              scope: _scopeForTab(_selectedTab),
              onVideoTap: _openVideo,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedSection extends StatelessWidget {
  const _FeedSection({
    required this.repository,
    required this.feed,
    required this.scope,
    required this.onVideoTap,
  });

  final VideoFeedRepository repository;
  final Future<List<Video>> feed;
  final BigGroup? scope;
  final ValueChanged<Video> onVideoTap;

  @override
  Widget build(BuildContext context) {
    if (!repository.hasVideos) {
      return const _FeedMessage(text: 'Videos aren\'t available yet.');
    }
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
        return VideosFeedBody(
          videos: videos,
          scope: scope,
          onVideoTap: onVideoTap,
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

class _Header extends StatelessWidget {
  const _Header({
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTopbar(
          mode: AppTopbarMode.nameOnly,
          showBackButton: false,
          gymName: mockGymGlobalMma.name,
          logoAsset: mockGymGlobalMma.logoAsset,
          streakDays: mockGymGlobalMma.streakDays,
          pointsLabel: mockGymGlobalMma.pointsLabel,
          rankBadgeAsset: mockGymGlobalMma.rankBadgeAsset,
        ),
        VideoCategoryTabs(
          tabs: tabs,
          selectedIndex: selectedIndex,
          onTabSelected: onTabSelected,
        ),
      ],
    );
  }
}
