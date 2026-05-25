import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/customization/brand_text.dart';
import 'package:mobile_app/shared/widgets/animation/loading_dots.dart';
import 'package:mobile_app/shared/widgets/animation/scale_reveal.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:mobile_app/customization/widgets/branded_image.dart';
import 'package:mobile_app/customization/widgets/branded_lottie.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

// Slower scale-in for the booked image so the "pop" reads as deliberate.
const Duration _kImageScaleDuration = Duration(milliseconds: 720);
// Lottie sized as a fraction of the smaller screen dimension — much
// bigger than a fixed 240px on modern phones, with a sensible cap so it
// doesn't dominate landscape.
const double _kDoneScreenFraction = 0.85;
const double _kDoneMaxSize = 420;
// Hold on the completed check before crossing into the booked content
// so the user can register the moment.
const Duration _kDoneSoakDuration = Duration(milliseconds: 1000);
// Faux "submitting…" loading dots before the success check. Plays for at
// least three full bounce cycles so the moment feels weighty before the
// check arrives.
const Duration _kLoadingDuration = Duration(milliseconds: 3000);
const String _kDoneLottieAsset = 'assets/animations/done.json';

// Total wall-clock time of the booked-content cascade (image scale + the
// caption's StaggeredReveal). The CTA appears once this elapses.
const Duration _kBookedCascadeDuration = Duration(milliseconds: 720 + 260);

const Duration _kCtaFadeIn = Duration(milliseconds: 220);

/// Confirmation screen shown after a successful class reservation. Three
/// phases: a brief "..." loading wave, then a Lottie "DONE" check in
/// brand color (held for a soak so the user registers it), then a slow
/// image scale-pop with the "Class Booked" caption sliding up under it.
/// The Continue button is hidden until every animation has settled —
/// this screen is intentionally **not skippable**.
class ClassBookedScreen extends StatefulWidget {
  const ClassBookedScreen({super.key});

  @override
  State<ClassBookedScreen> createState() => _ClassBookedScreenState();
}

class _ClassBookedScreenState extends State<ClassBookedScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _doneCtrl = AnimationController(vsync: this);
  bool _showDone = false;
  bool _showContent = false;
  bool _showCta = false;
  Timer? _loadingTimer;
  Timer? _soakTimer;
  Timer? _ctaTimer;

  @override
  void initState() {
    super.initState();
    _doneCtrl.addStatusListener(_onDoneStatus);
    _loadingTimer = Timer(_kLoadingDuration, () {
      if (mounted) setState(() => _showDone = true);
    });
  }

  void _onDoneStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    _soakTimer = Timer(_kDoneSoakDuration, _advanceToContent);
  }

  void _advanceToContent() {
    if (!mounted) return;
    setState(() => _showContent = true);
    _ctaTimer = Timer(_kBookedCascadeDuration, () {
      if (mounted) setState(() => _showCta = true);
    });
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _soakTimer?.cancel();
    _ctaTimer?.cancel();
    _doneCtrl
      ..removeStatusListener(_onDoneStatus)
      ..dispose();
    super.dispose();
  }

  Widget _buildBody() {
    if (_showContent) return const _BookedContent();
    if (_showDone) {
      return Center(child: _DoneIntro(controller: _doneCtrl));
    }
    return const Center(child: LoadingDots());
  }

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildBody()),
          Padding(
            padding: EdgeInsets.only(bottom: DesignConstants.spacingBig),
            child: IgnorePointer(
              ignoring: !_showCta,
              child: AnimatedOpacity(
                opacity: _showCta ? 1.0 : 0.0,
                duration: _kCtaFadeIn,
                curve: Curves.easeOutQuart,
                child: AppPrimaryButton(
                  text: 'Continue',
                  fullWidth: true,
                  borderRadius: DesignConstants.radiusBig,
                  onPressed: () => Navigator.of(
                    context,
                  ).pushReplacementNamed(AppRoutes.videoRecc),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneIntro extends StatelessWidget {
  const _DoneIntro({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final size = math.min(
      math.min(screen.width, screen.height) * _kDoneScreenFraction,
      _kDoneMaxSize,
    );
    return SizedBox(
      width: size,
      height: size,
      child: BrandedLottie(
        slot: CombatDenSlots.bookingCelebration,
        fallbackAsset: _kDoneLottieAsset,
        controller: controller,
        fit: BoxFit.contain,
        onLoaded: (composition) {
          controller
            ..duration = composition.duration
            ..forward();
        },
      ),
    );
  }
}

class _BookedContent extends StatelessWidget {
  const _BookedContent();

  @override
  Widget build(BuildContext context) {
    final captionDelay = _kImageScaleDuration;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingBig,
      children: [
        ScaleReveal(
          duration: _kImageScaleDuration,
          child: BrandedImage(
            slot: CombatDenSlots.celebrationImage,
            fallback: ApiImage.asset('class_booked_celebration.png'),
            fit: BoxFit.contain,
          ),
        ),
        StaggeredReveal(
          delay: captionDelay,
          child: Text(
            BrandText.value(
              CombatDenSlots.classBookedHeadline,
              fallback: 'Class Booked',
            ),
            style: DesignConstants.big2,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
