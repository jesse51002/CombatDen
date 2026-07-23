import 'dart:async';

import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_dots.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_panel.dart';

/// How long each showcase slide dwells before the next one fades in.
const Duration kKioskShowcaseInterval = Duration(seconds: 5);

/// The cross-fade between two slides (mockup `.slide` opacity transition).
const Duration kKioskShowcaseFade = Duration(milliseconds: 450);

/// The welcome screen's right panel (mockup `.showcase`): a fixed head
/// (mono eyebrow + the current slide's title) over an auto-advancing slide
/// stage, closed by the clickable dot pager and its caption.
///
/// The rotation is pure local UI state — a plain [Timer], never the flow
/// cubit, so it cannot touch the modal's own 60-second auto-close. Tapping a
/// dot jumps and restarts the dwell. With reduced motion requested the
/// rotation is off and the caption says so; the dots still work.
///
/// Every slide sits in ONE box (a [Stack], so the box is as tall as the
/// tallest slide) and only its opacity changes — the mockup's rule that "the
/// one-page welcome fit holds on every slide", i.e. the modal never resizes
/// mid-rotation.
class KioskAppShowcase extends StatefulWidget {
  final List<KioskShowcaseSlide> slides;

  const KioskAppShowcase({super.key, required this.slides});

  @override
  State<KioskAppShowcase> createState() => _KioskAppShowcaseState();
}

class _KioskAppShowcaseState extends State<KioskAppShowcase> {
  Timer? _timer;
  int _index = 0;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs once right after initState (where MediaQuery isn't readable yet)
    // and again whenever the accessibility setting changes; [_restart] is
    // idempotent, so re-arming here is safe.
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (_reduceMotion || widget.slides.length < 2) return;
    _timer = Timer.periodic(kKioskShowcaseInterval, (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.slides.length);
    });
  }

  void _jumpTo(int i) {
    setState(() => _index = i);
    _restart(); // a manual pick re-arms the full dwell
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    // A gym with nothing to show at all: the modal drops this panel entirely
    // rather than rendering an empty one, so this is unreachable in practice —
    // it is here so the widget is safe to hand any slide list.
    if (slides.isEmpty) return const SizedBox.shrink();
    // Guard a shrinking list (a slide switching off between builds).
    final index = _index.clamp(0, slides.length - 1);
    return KioskGlancePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          _Head(title: slides[index].title),
          Expanded(child: _SlideStage(slides: slides, index: index)),
          KioskShowcaseDots(
            labels: [for (final s in slides) s.title],
            index: index,
            onSelected: _jumpTo,
          ),
          _Note(slides: slides, reduceMotion: _reduceMotion),
        ],
      ),
    );
  }
}

/// The fixed head: the mono eyebrow over the rotating slide title.
class _Head extends StatelessWidget {
  final String title;

  const _Head({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text('IN THE APP', style: DesignConstants.kioskEyebrow),
        Text(
          title,
          style: DesignConstants.kioskPanelTitle,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// All slides stacked in one box; only the active one is visible and
/// hit-testable, so the panel keeps a stable height as they rotate.
class _SlideStage extends StatelessWidget {
  final List<KioskShowcaseSlide> slides;
  final int index;

  const _SlideStage({required this.slides, required this.index});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        for (var i = 0; i < slides.length; i++)
          IgnorePointer(
            ignoring: i != index,
            child: AnimatedOpacity(
              opacity: i == index ? 1 : 0,
              duration: kKioskShowcaseFade,
              curve: Curves.easeOut,
              child: slides[i].body,
            ),
          ),
      ],
    );
  }
}

/// The caption under the dots (mockup `.showcase-note`) — derived from the
/// live slide list, so it never advertises a slide that isn't there (e.g. a
/// no-ranks gym), and it tells the truth when rotation is off.
class _Note extends StatelessWidget {
  final List<KioskShowcaseSlide> slides;
  final bool reduceMotion;

  const _Note({required this.slides, required this.reduceMotion});

  @override
  Widget build(BuildContext context) {
    final titles = slides.map((s) => s.title.toLowerCase()).join(' · ');
    return Text(
      reduceMotion ? 'Tap a dot to browse' : 'Auto-rotates: $titles',
      style: DesignConstants.kioskMicro.copyWith(
        fontWeight: FontWeight.w500,
        color: DesignConstants.text2nd,
      ),
      textAlign: TextAlign.center,
    );
  }
}
