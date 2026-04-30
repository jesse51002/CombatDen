import 'package:flutter/material.dart';
import 'package:mobile_app/core/branding/brand.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';
import 'package:mobile_app/features/class_booking/presentation/screens/class_booked_screen.dart';
import 'package:mobile_app/features/class_booking/presentation/screens/class_screen.dart';
import 'package:mobile_app/features/home/presentation/screens/home_screen.dart';
import 'package:mobile_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:mobile_app/features/rewards/presentation/screens/my_rewards_screen.dart';
import 'package:mobile_app/features/rewards/presentation/screens/points_store_screen.dart';
import 'package:mobile_app/features/rewards/presentation/screens/summary_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/points_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/rank_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/rewards_card_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/streak_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/wins_screen.dart';
import 'package:mobile_app/features/videos/presentation/screens/specific_videos_screen.dart';
import 'package:mobile_app/features/videos/presentation/screens/video_recc_screen.dart';
import 'package:mobile_app/features/videos/presentation/screens/videos_screen.dart';
import 'package:mobile_app/shared/themes/app_theme.dart';

void main() => runApp(const MobileAppRoot());

class MobileAppRoot extends StatefulWidget {
  const MobileAppRoot({super.key});

  @override
  State<MobileAppRoot> createState() => _MobileAppRootState();
}

class _MobileAppRootState extends State<MobileAppRoot> {
  final _brand = ValueNotifier<Brand>(Brand.combatDen);

  @override
  void dispose() {
    _brand.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BrandScope(
      notifier: _brand,
      child: ValueListenableBuilder<Brand>(
        valueListenable: _brand,
        builder: (context, brand, _) {
          return MaterialApp(
            title: 'CombatDen',
            theme: AppTheme.dark(brand.constants),
            debugShowCheckedModeBanner: false,
            initialRoute: AppRoutes.home,
            routes: {
              AppRoutes.home: (_) => const HomeScreen(),
              AppRoutes.classDetail: (_) => const ClassScreen(),
              AppRoutes.reservingLoading: (_) => const ClassBookedScreen(),
              AppRoutes.videos: (_) => const VideosScreen(),
              AppRoutes.videoDetail: (_) => const SpecificVideosScreen(),
              AppRoutes.videoRecc: (_) => const VideoReccScreen(),
              AppRoutes.profile: (_) => const ProfileScreen(),
              AppRoutes.myRewards: (_) => const MyRewardsScreen(),
              AppRoutes.pointsStore: (_) => const PointsStoreScreen(),
              AppRoutes.summary: (_) => const SummaryScreen(),
              AppRoutes.postClassStreak: (_) => const StreakScreen(),
              AppRoutes.postClassWins: (_) => const WinsScreen(),
              AppRoutes.postClassPoints: (_) => const PointsScreen(),
              AppRoutes.postClassRewards: (_) => const RewardsCardScreen(),
              AppRoutes.postClassRank: (_) => const RankScreen(),
            },
          );
        },
      ),
    );
  }
}
