import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/features/videos/data/mock_videos.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_category_tabs.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_card.dart';

const List<String> _kCategoryTabs = ['All', 'Explore', 'Learn', 'Fights'];
const int _kAllTabIndex = 0;
const int _kDefaultTabIndex = 2; // Learn

class SpecificVideosScreen extends StatefulWidget {
  const SpecificVideosScreen({super.key});

  @override
  State<SpecificVideosScreen> createState() => _SpecificVideosScreenState();
}

class _SpecificVideosScreenState extends State<SpecificVideosScreen> {
  int? _selectedTab;

  void _onTabSelected(int index) {
    if (index == _kAllTabIndex) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.videos);
      return;
    }
    setState(() => _selectedTab = index);
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final selected = args is MockVideo ? args : mockFightingLessons.first;
    final initialTab = args is int ? args : _kDefaultTabIndex;
    final activeTab = _selectedTab ?? initialTab;

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
              selectedIndex: activeTab,
              onTabSelected: _onTabSelected,
            ),
            const _SectionTitle(title: 'Fighting Lessons'),
            _VideoList(videos: _orderedVideos(selected)),
          ],
        ),
      ),
    );
  }

  List<MockVideo> _orderedVideos(MockVideo selected) {
    final rest = mockFightingLessons
        .where((v) => v.id != selected.id)
        .toList(growable: false);
    return [selected, ...rest];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.selectedIndex, required this.onTabSelected});

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
          tabs: _kCategoryTabs,
          selectedIndex: selectedIndex,
          onTabSelected: onTabSelected,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, textAlign: TextAlign.center, style: DesignConstants.h2);
  }
}

class _VideoList extends StatelessWidget {
  const _VideoList({required this.videos});

  final List<MockVideo> videos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        for (final v in videos)
          VideoReccCard(
            title: v.title,
            metaLabel: v.metaLabel,
            thumbnailAsset: v.thumbnailAsset,
            creatorPfpAsset: v.creatorPfpAsset,
            onTap: () => Navigator.of(context).pushReplacementNamed(
              AppRoutes.videoDetail,
              arguments: v,
            ),
          ),
      ],
    );
  }
}
