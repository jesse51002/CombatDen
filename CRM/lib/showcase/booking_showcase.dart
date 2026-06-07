import 'dart:async';

import 'package:flutter/material.dart';

import 'package:crm/showcase/showcase_assets.dart';
import 'package:crm/showcase/showcase_slots.dart';
import 'package:crm/showcase/showcase_tokens.dart';
import 'package:crm/showcase/support/showcase_primary_button.dart';
import 'package:crm/showcase/support/showcase_scaffold.dart';
import 'package:crm/showcase/support/staggered_reveal.dart';
import 'package:theme_flutter/theme/animation/scale_reveal.dart';
import 'package:theme_flutter/theme/theme_image.dart';
import 'package:theme_flutter/theme/theme_text.dart';

// Clone of MobileApp's class_booked_screen _k consts.
const Duration _kImageScaleDuration = Duration(milliseconds: 720);
const Duration _kBookedCascadeDuration = Duration(milliseconds: 720 + 260);
const Duration _kCtaFadeIn = Duration(milliseconds: 220);
// Hold the finished booked content before the loop restarts.
const Duration _kLoopHold = Duration(milliseconds: 2200);
// Mirror MobileApp's celebration-image cap so the showcase matches the real
// screen's proportions on tall phone-frame previews.
const double _kCelebrationMaxHeight = 420;

/// Visual clone of the member app's **class-booked celebration**
/// (`ClassBookedScreen`): a slow image scale-pop with the "Class Booked"
/// caption sliding up under it and the CTA fading in. Loops.
class BookingShowcase extends StatefulWidget {
  const BookingShowcase({super.key, this.loop = true, this.onCycleComplete});

  final bool loop;
  final VoidCallback? onCycleComplete;

  @override
  State<BookingShowcase> createState() => _BookingShowcaseState();
}

class _BookingShowcaseState extends State<BookingShowcase> {
  bool _showCta = false;
  int _cycle = 0; // re-keys the body so animations replay each loop
  Timer? _ctaTimer;
  Timer? _loopTimer;

  @override
  void initState() {
    super.initState();
    _playCycle();
  }

  void _playCycle() {
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
      _showCta = false;
      _cycle++;
    });
    _playCycle();
  }

  @override
  void dispose() {
    _ctaTimer?.cancel();
    _loopTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShowcaseScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _BookedContent(key: ValueKey(_cycle))),
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

class _BookedContent extends StatelessWidget {
  const _BookedContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: ShowcaseTokens.spacingBig,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: _kCelebrationMaxHeight,
            ),
            child: ScaleReveal(
              duration: _kImageScaleDuration,
              child: Image(
                image: ThemeImage.image(
                  ShowcaseSlots.celebrationImage,
                  fallback: ShowcaseAsset.image(
                    'class_booked_celebration.png',
                  ),
                ),
                fit: BoxFit.contain,
              ),
            ),
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
