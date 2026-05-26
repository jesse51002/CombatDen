import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:customization_engine/showcase/showcase_assets.dart';
import 'package:customization_engine/showcase/showcase_slots.dart';
import 'package:customization_engine/showcase/showcase_tokens.dart';
import 'package:customization_engine/showcase/support/showcase_primary_button.dart';
import 'package:customization_engine/showcase/support/showcase_scaffold.dart';
import 'package:customization_engine/showcase/support/staggered_reveal.dart';
import 'package:customization_engine/theme/lottie/scale_reveal.dart';
import 'package:customization_engine/theme/lottie/theme_lottie.dart';
import 'package:customization_engine/theme/theme_image.dart';
import 'package:customization_engine/theme/theme_text.dart';

// Clone of MobileApp's class_booked_screen _k consts.
const Duration _kImageScaleDuration = Duration(milliseconds: 720);
const double _kDoneScreenFraction = 0.85;
const double _kDoneMaxSize = 420;
const Duration _kDoneSoakDuration = Duration(milliseconds: 1000);
const Duration _kBookedCascadeDuration = Duration(milliseconds: 720 + 260);
const Duration _kCtaFadeIn = Duration(milliseconds: 220);
// Hold the finished booked content before the loop restarts.
const Duration _kLoopHold = Duration(milliseconds: 2200);

/// Exact visual clone of the member app's **class-booked celebration**
/// (`ClassBookedScreen`): the branded "DONE" Lottie check (held for a soak),
/// then a slow image scale-pop with the "Class Booked" caption sliding up
/// under it and the CTA fading in. Loops.
class BookingShowcase extends StatefulWidget {
  const BookingShowcase({super.key, this.loop = true, this.onCycleComplete});

  final bool loop;
  final VoidCallback? onCycleComplete;

  @override
  State<BookingShowcase> createState() => _BookingShowcaseState();
}

class _BookingShowcaseState extends State<BookingShowcase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _doneCtrl = AnimationController(vsync: this);
  bool _showContent = false;
  bool _showCta = false;
  int _cycle = 0; // re-keys the body so animations replay each loop
  Timer? _soakTimer;
  Timer? _ctaTimer;
  Timer? _loopTimer;

  @override
  void initState() {
    super.initState();
    _doneCtrl.addStatusListener(_onDoneStatus);
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
    _loopTimer = Timer(_kBookedCascadeDuration + _kLoopHold, _restart);
  }

  void _restart() {
    if (!mounted) return;
    widget.onCycleComplete?.call();
    if (!widget.loop) return;
    setState(() {
      _showContent = false;
      _showCta = false;
      _cycle++;
    });
    _doneCtrl
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _soakTimer?.cancel();
    _ctaTimer?.cancel();
    _loopTimer?.cancel();
    _doneCtrl
      ..removeStatusListener(_onDoneStatus)
      ..dispose();
    super.dispose();
  }

  Widget _buildBody() {
    if (_showContent) return _BookedContent(key: ValueKey(_cycle));
    return Center(child: _DoneIntro(controller: _doneCtrl));
  }

  @override
  Widget build(BuildContext context) {
    return ShowcaseScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildBody()),
          Padding(
            padding: const EdgeInsets.only(bottom: ShowcaseTokens.spacingBig),
            child: IgnorePointer(
              ignoring: !_showCta,
              child: AnimatedOpacity(
                opacity: _showCta ? 1.0 : 0.0,
                duration: _kCtaFadeIn,
                curve: Curves.easeOutQuart,
                child: ShowcasePrimaryButton(
                  text: 'Continue',
                  fullWidth: true,
                  borderRadius: ShowcaseTokens.radiusBig,
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
      child: ThemeLottie(
        slot: ShowcaseSlots.bookingCelebration,
        fallbackAsset: ShowcaseAsset.animation('done.json'),
        controller: controller,
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
  const _BookedContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: ShowcaseTokens.spacingBig,
      children: [
        ScaleReveal(
          duration: _kImageScaleDuration,
          child: Image(
            image: ThemeImage.image(
              ShowcaseSlots.celebrationImage,
              fallback: ShowcaseAsset.image('class_booked_celebration.png'),
            ),
            fit: BoxFit.contain,
          ),
        ),
        StaggeredReveal(
          delay: _kImageScaleDuration,
          child: Text(
            ThemeText.value(
              ShowcaseSlots.classBookedHeadline,
              fallback: 'Class Booked',
            ),
            style: ShowcaseTokens.big2,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
