import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_config.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/app_routes.dart';
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
import 'package:mobile_app/features/style_select/presentation/screens/style_select_screen.dart';
import 'package:mobile_app/features/videos/presentation/screens/tag_videos_screen.dart';
import 'package:mobile_app/features/videos/presentation/screens/video_recc_screen.dart';
import 'package:mobile_app/features/videos/presentation/screens/videos_screen.dart';
import 'package:customization_engine/customization_runtime.dart';
import 'package:mobile_app/shared/themes/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One call: wiring, fetch, disk cache and image pre-warm are
  // all internal. Blocks on the small JSON (5s cap) before the
  // first frame so the UI paints branded.
  await CustomizationRuntime.initialize(
    appId: AppConfig.appId,
    designId: AppConfig.designId,
    expectedColors: CombatDenSlots.expectedColors,
    expectedImages: CombatDenSlots.expectedImages,
    expectedFonts: CombatDenSlots.expectedFonts,
    expectedText: CombatDenSlots.expectedText,
    expectedIcons: CombatDenSlots.expectedIcons,
    expectedLotties: CombatDenSlots.expectedLotties,
  );

  runApp(const MobileAppRoot());
}

class MobileAppRoot extends StatelessWidget {
  const MobileAppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole app when the active customization changes, so a
    // live style switch (CustomizationRuntime.selectDesign) re-themes
    // everything: AppTheme + DesignConstants re-resolve, ThemeImage slots
    // re-fetch. The builder runs on first load too (harmless no-op).
    return ListenableBuilder(
      listenable: CustomizationRuntime.changes,
      builder: (context, _) {
        return MaterialApp(
          // Re-key on the active design so a live style switch rebuilds
          // the whole tree from a fresh Home. Needed because widgets read
          // DesignConstants static getters (not Theme.of), so the
          // Navigator's already-pushed routes won't otherwise re-theme.
          key: ValueKey(CustomizationRuntime.activeDesignId),
          title: 'CombatDen',
          theme: AppTheme.forCanvas(),
          debugShowCheckedModeBanner: false,
          initialRoute: AppRoutes.home,
          routes: {
            AppRoutes.home: (_) => const HomeScreen(),
            AppRoutes.classDetail: (_) => const ClassScreen(),
            AppRoutes.reservingLoading: (_) => const ClassBookedScreen(),
            AppRoutes.videos: (_) => const VideosScreen(),
            AppRoutes.videoTagList: (_) => const TagVideosScreen(),
            AppRoutes.videoRecc: (_) => const VideoReccScreen(),
            AppRoutes.profile: (_) => const ProfileScreen(),
            AppRoutes.styleSelect: (_) => const StyleSelectScreen(),
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
    );
  }
}
