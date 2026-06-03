import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/theme/theme_image.dart';

import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/presentation/screens/class_booked_screen.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/features/home/presentation/screens/home_screen.dart';
import 'package:mobile_app/features/rewards/presentation/screens/points_store_screen.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/points/points_body.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_body.dart';
import 'package:mobile_app/features/stats/presentation/widgets/wins/wins_body.dart';
import 'package:mobile_app/features/videos/presentation/screens/video_recc_screen.dart';
import 'package:mobile_app/features/videos/presentation/screens/videos_screen.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';
import 'capture_frame.dart';

// Home logo scale-in intro geometry. The logo starts big and upper-centred, then
// scales down + flies up into its real topbar position; the brand background
// fades out to reveal the loaded home, then the splash logo hands off to the real
// one. Final position matches GymHeader's 100×100 logo at topbar padding-top(32).
const double _kLogoFinalCenterY = 82; // topbar padding(32) + logo half(50)
const double _kLogoFinalSize = 100; // GymHeader logo is 100×100
const double _kLogoStartScale = 2.8; // start ~2.8× the final size
const double _kLogoStartCenterYFrac = 0.42; // big logo sits upper-middle
const double _kBgFadeStart = 0.62; // brand bg fades out from here
const double _kLogoFadeStart = 0.9; // splash logo fades to hand off to the real one

/// The app screens captured by `capture_app_main.dart`. home/points/streak are
/// the animated clips; rewards/videos/wins/booked/videoBefore are static
/// screenshot-only screens (wins/booked/videoBefore grab a settled final frame
/// via the global capture clock — see `_captureSettledFrame`).
enum AppScreen { home, points, streak, rewards, videos, wins, booked, videoBefore }

/// Mounts the requested [screen] inside the shared fixed-size [CaptureFrame]
/// (at [stageHeight]):
/// - [AppScreen.home] → the real [HomeScreen] (its PageView opens on the
///   not-booked class-schedule page); held static by the harness,
/// - [AppScreen.points] / [AppScreen.streak] → the celebration body inside the
///   real [PostClassScaffold], but with [ctaController] left permanently
///   "animating" (so the Continue CTA stays hidden) and no close (X) button —
///   the body's intro + stats cascade are driven by the global capture clock.
///
/// The bodies are mounted with no controller of their own (clock-driven under
/// capture), so the scaffold framing is faithful but the chrome is suppressed.
class AppStage extends StatelessWidget {
  const AppStage({
    super.key,
    required this.boundaryKey,
    required this.screen,
    required this.stageWidth,
    required this.stageHeight,
    required this.pixelRatio,
    required this.ctaController,
    this.logoIntroProgress = -1,
  });

  final GlobalKey boundaryKey;
  final AppScreen screen;
  final double stageWidth;
  final double stageHeight;
  final double pixelRatio;

  /// Held "animating" by the harness so the celebration screens' Continue CTA
  /// stays hidden for the whole clip. Unused by [AppScreen.home].
  final PostClassController ctaController;

  /// Home only: the logo scale-in progress 0→1, driven by the harness. <0 means
  /// no splash overlay (the plain home, e.g. the hold after the intro).
  final double logoIntroProgress;

  @override
  Widget build(BuildContext context) {
    return CaptureFrame(
      boundaryKey: boundaryKey,
      stageWidth: stageWidth,
      stageHeight: stageHeight,
      pixelRatio: pixelRatio,
      // Re-key on the active design so a theme switch rebuilds the (const-heavy)
      // screen subtree from scratch — otherwise a static screen like Home keeps
      // the theme it first mounted with. Mirrors the scroll reel's CaptureStage.
      // The theme settles before capture, so the key is stable during the clip.
      child: KeyedSubtree(
        key: ValueKey(ThemeRuntime.activeDesignId),
        child: _screenChild(),
      ),
    );
  }

  Widget _screenChild() {
    switch (screen) {
      case AppScreen.home:
        // Always wrap so the splash overlay can appear/disappear without
        // reparenting (and resetting) the HomeScreen subtree.
        return _LogoIntro(
          progress: logoIntroProgress,
          stageWidth: stageWidth,
          stageHeight: stageHeight,
          child: const HomeScreen(),
        );
      case AppScreen.points:
        return _hiddenCta(const PointsBody(stats: mockPointsStats));
      case AppScreen.streak:
        return _hiddenCta(const StreakBody(stats: mockStreakStats));
      case AppScreen.rewards:
        return const PointsStoreScreen();
      case AppScreen.videos:
        return const VideosScreen();
      case AppScreen.wins:
        // The "Today's wins" recap — the post-class flow's final stats card.
        // Clean (CTA faded out, no X), matching the points/streak clips.
        return _hiddenCta(const WinsBody(stats: mockWinsStats));
      case AppScreen.booked:
        // The settled "Class Booked" confirmation (booked image + caption,
        // no loading dots / checkmark / CTA) — the existing capture hook.
        return const ClassBookedScreen(captureContentOnly: true);
      case AppScreen.videoBefore:
        // The real "Video Before Class" recommendation screen.
        return const VideoReccScreen();
    }
  }

  /// The real celebration scaffold, framed exactly like the shipped screen, but
  /// with the CTA hidden (controller stays animating) and no X (onClose null).
  Widget _hiddenCta(Widget body) {
    return PostClassScaffold(
      controller: ctaController,
      body: body,
      ctaLabel: 'Continue',
      onCtaPressed: () {},
    );
  }
}

/// The home intro splash. [child] (the home page) is always the base layer; when
/// [progress] >= 0 a brand-coloured overlay with the scaling brand logo sits on
/// top. As progress goes 0→1 the logo scales down from big-and-centred into the
/// real topbar position, the brand background fades out to reveal the (loaded)
/// home, and the splash logo fades to hand off to the real topbar logo.
class _LogoIntro extends StatelessWidget {
  const _LogoIntro({
    required this.progress,
    required this.stageWidth,
    required this.stageHeight,
    required this.child,
  });

  final double progress;
  final double stageWidth;
  final double stageHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (progress >= 0) _overlay(),
      ],
    );
  }

  Widget _overlay() {
    final eased = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    const finalSize = _kLogoFinalSize;
    final startSize = finalSize * _kLogoStartScale;
    final finalCenter = Offset(stageWidth / 2, _kLogoFinalCenterY);
    final startCenter = Offset(stageWidth / 2, stageHeight * _kLogoStartCenterYFrac);
    final size = lerpDouble(startSize, finalSize, eased)!;
    final center = Offset.lerp(startCenter, finalCenter, eased)!;
    final bgOpacity =
        1 - ((progress - _kBgFadeStart) / (1 - _kBgFadeStart)).clamp(0.0, 1.0);
    final logoOpacity = 1 -
        ((progress - _kLogoFadeStart) / (1 - _kLogoFadeStart)).clamp(0.0, 1.0);
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: bgOpacity,
              child: ColoredBox(color: DesignConstants.backgroundColor),
            ),
          ),
          Positioned(
            left: center.dx - size / 2,
            top: center.dy - size / 2,
            width: size,
            height: size,
            child: Opacity(
              opacity: logoOpacity,
              child: Image(
                image: ThemeImage.image(
                  CombatDenSlots.logoPrimary,
                  fallback: ApiImage.asset(mockGym.logoAsset),
                ),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
