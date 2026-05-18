import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/features/videos/data/mock_videos.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_category_tabs.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_body.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

const List<String> _kCategoryTabs = ['All', 'Explore', 'Learn', 'Fights'];

class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  static const int _kAllTabIndex = 0;

  void _openVideo(BuildContext context, MockVideo video) {
    Navigator.of(context).pushNamed(AppRoutes.videoDetail, arguments: video);
  }

  void _onTabSelected(int index) {
    if (index == _kAllTabIndex) return;
    Navigator.of(
      context,
    ).pushReplacementNamed(AppRoutes.videoDetail, arguments: index);
  }

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
              tabs: _kCategoryTabs,
              selectedIndex: _kAllTabIndex,
              onTabSelected: _onTabSelected,
            ),
            VideosFeedBody(
              onVideoTap: (v) => _openVideo(context, v),
            ),
          ],
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
