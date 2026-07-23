import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_app/core/app_config.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/config/supabase_config.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/class_booking/presentation/screens/class_booked_screen.dart';
import 'package:mobile_app/features/class_booking/presentation/screens/class_screen.dart';
import 'package:mobile_app/features/home/presentation/screens/home_screen.dart';
import 'package:mobile_app/features/login/bloc/login_bloc.dart';
import 'package:mobile_app/features/login/bloc/login_event.dart';
import 'package:mobile_app/features/login/data/repositories/auth_repository.dart';
import 'package:mobile_app/features/login/presentation/screens/auth_gate.dart';
import 'package:mobile_app/features/member_select/presentation/screens/switch_profile_screen.dart';
import 'package:mobile_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:mobile_app/features/qr_checkin/presentation/screens/checkin_confirm_screen.dart';
import 'package:mobile_app/features/qr_checkin/presentation/screens/checkin_pick_class_screen.dart';
import 'package:mobile_app/features/qr_checkin/presentation/screens/checkin_scanner_screen.dart';
import 'package:mobile_app/features/rewards/presentation/screens/my_rewards_screen.dart';
import 'package:mobile_app/features/rewards/presentation/screens/points_store_screen.dart';
import 'package:mobile_app/features/rewards/presentation/screens/summary_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/points_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/rank_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/rewards_card_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/streak_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/wins_screen.dart';
import 'package:mobile_app/features/videos/presentation/screens/tag_videos_screen.dart';
import 'package:mobile_app/features/videos/presentation/screens/video_recc_screen.dart';
import 'package:mobile_app/features/videos/presentation/screens/videos_screen.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:mobile_app/shared/themes/app_theme.dart';

/// The app's named-route table. Shared by the authenticated app shell's nested
/// navigator (via [AuthGate]'s `onGenerateRoute`) and the root navigator.
final Map<String, WidgetBuilder> _routeBuilders = {
  AppRoutes.home: (_) => const HomeScreen(),
  AppRoutes.classDetail: (_) => const ClassScreen(),
  AppRoutes.reservingLoading: (_) => const ClassBookedScreen(),
  AppRoutes.videos: (_) => const VideosScreen(),
  AppRoutes.videoTagList: (_) => const TagVideosScreen(),
  AppRoutes.videoRecc: (_) => const VideoReccScreen(),
  AppRoutes.profile: (_) => const ProfileScreen(),
  AppRoutes.memberSelect: (_) => const SwitchProfileScreen(),
  AppRoutes.checkinScanner: (_) => const CheckinScannerScreen(),
  AppRoutes.checkinPickClass: (_) => const CheckinPickClassScreen(),
  AppRoutes.checkinConfirm: (_) => const CheckinConfirmScreen(),
  AppRoutes.myRewards: (_) => const MyRewardsScreen(),
  AppRoutes.pointsStore: (_) => const PointsStoreScreen(),
  AppRoutes.summary: (_) => const SummaryScreen(),
  AppRoutes.postClassStreak: (_) => const StreakScreen(),
  AppRoutes.postClassWins: (_) => const WinsScreen(),
  AppRoutes.postClassPoints: (_) => const PointsScreen(),
  AppRoutes.postClassRewards: (_) => const RewardsCardScreen(),
  AppRoutes.postClassRank: (_) => const RankScreen(),
};

Route<dynamic> _onGenerateRoute(RouteSettings settings) {
  final builder =
      _routeBuilders[settings.name] ?? _routeBuilders[AppRoutes.home]!;
  return MaterialPageRoute<dynamic>(builder: builder, settings: settings);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Best-effort auth backend bring-up before the first frame. A failure
  // (missing key, offline Supabase) is logged and the app still boots
  // degraded rather than showing a blank screen.
  try {
    await SupabaseConfig.initialize();
  } catch (e, s) {
    log('Supabase init failed', error: e, stackTrace: s);
  }

  // One call: wiring, fetch, disk cache and image pre-warm are all internal.
  // Blocks on the small JSON (5s cap) before the first frame so the UI paints
  // branded on the bundled default design.
  await ThemeRuntime.initialize(
    appId: AppConfig.appId,
    designId: AppConfig.designId,
    expectedColors: CombatDenSlots.expectedColors,
    expectedImages: CombatDenSlots.expectedImages,
    expectedFonts: CombatDenSlots.expectedFonts,
    expectedText: CombatDenSlots.expectedText,
    expectedIcons: CombatDenSlots.expectedIcons,
  );

  runApp(const MobileAppRoot());
}

class MobileAppRoot extends StatefulWidget {
  const MobileAppRoot({super.key});

  @override
  State<MobileAppRoot> createState() => _MobileAppRootState();
}

class _MobileAppRootState extends State<MobileAppRoot> {
  /// The one app-lifetime auth bloc, provided above [AuthGate]. Owned here (not
  /// via `BlocProvider(create:)`) so `ApiClient.onUnauthorized` can drive it.
  late final LoginBloc _loginBloc = LoginBloc(authRepository: AuthRepository());

  @override
  void initState() {
    super.initState();
    // An unrecoverable 401 (refresh failed) signs the session out, dropping the
    // gate back to the login screen.
    ApiClient.onUnauthorized =
        () => _loginBloc.add(const LoginSignOutRequested());
  }

  @override
  void dispose() {
    ApiClient.onUnauthorized = null;
    _loginBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the app's ThemeData when the active customization changes so
    // stock Material chrome re-resolves. The authenticated app shell carries
    // its own re-key on the active design so already-pushed screens re-theme;
    // the gate/login stay above that boundary (login runs on the bundled
    // default), so they are never remounted by a member's theme switch.
    return ListenableBuilder(
      listenable: ThemeRuntime.changes,
      builder: (context, _) {
        return MaterialApp(
          title: 'CombatDen',
          theme: AppTheme.forCanvas(),
          debugShowCheckedModeBanner: false,
          onGenerateRoute: _onGenerateRoute,
          home: BlocProvider<LoginBloc>.value(
            value: _loginBloc,
            child: AuthGate(onGenerateRoute: _onGenerateRoute),
          ),
        );
      },
    );
  }
}
