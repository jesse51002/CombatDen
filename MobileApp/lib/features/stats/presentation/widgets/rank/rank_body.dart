import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/shared/widgets/animation/count_up_text.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:customization_engine/theme/theme_image.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';

// Per-screen layout/timing math, file-scoped per CLAUDE.md's _k carve-out.
const Duration _kEntrance = Duration(milliseconds: 420);
const Duration _kHold = Duration(milliseconds: 800);
const Duration _kShrink = Duration(milliseconds: 700);
const double _kBigBelt = 280;
const double _kBeltStartScale = 0.5;
// Slot dimensions copied from `RankHeader`'s belt — same row pattern as
// the profile screen.
const double _kSlotWidth = 77;
const double _kSlotHeight = 50;

/// Rank celebration:
/// 1. Big belt enters with a bold scale + fade pop, centered.
/// 2. Belt holds full-size center stage.
/// 3. Belt **physically shrinks and translates** to its final UI position
///    inside a small "rank header" row, while the surrounding stats
///    content (count-up, "classes in rank", caption) cross-fades in
///    around it.
///
/// The belt is a single rendered widget the whole time — its left/top/
/// width/height interpolate frame-by-frame from "centered + 280px" to
/// "slot position + 77×50". The slot's actual position is measured via a
/// `GlobalKey` post-frame, so the landing point matches the layout
/// exactly regardless of screen size or rank-text width.
class RankBody extends StatefulWidget {
  const RankBody({super.key, required this.stats, this.controller});

  final MockRankStats stats;
  final PostClassController? controller;

  @override
  State<RankBody> createState() => _RankBodyState();
}

class _RankBodyState extends State<RankBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _kEntrance + _kHold + _kShrink,
  );

  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _slotKey = GlobalKey();

  Rect? _slotRect;

  @override
  void initState() {
    super.initState();
    _ctrl
      ..addStatusListener(_onStatus)
      ..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureSlot());
    widget.controller?.registerSkipHandler(_skipToFinal);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      widget.controller?.markDone();
    }
  }

  void _measureSlot() {
    if (!mounted || _slotRect != null) return;
    final slotBox = _slotKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (slotBox == null || stackBox == null) return;
    if (!slotBox.hasSize || !stackBox.hasSize) return;
    final pos = slotBox.localToGlobal(Offset.zero, ancestor: stackBox);
    setState(() => _slotRect = pos & slotBox.size);
  }

  void _skipToFinal() {
    if (!mounted) return;
    _ctrl.value = 1.0;
    widget.controller?.markDone();
  }

  @override
  void dispose() {
    widget.controller?.clearSkipHandler();
    _ctrl
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder lifted above the Stack so we can compute the belt's
    // "centered + big" rect in stack-local coordinates and emit a
    // `Positioned` as a *direct* child of the Stack (Positioned can't be
    // nested under another widget between itself and its Stack).
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackW = constraints.maxWidth;
        final stackH = constraints.maxHeight;
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            final totalMs =
                (_kEntrance + _kHold + _kShrink).inMilliseconds.toDouble();
            final entranceEnd = _kEntrance.inMilliseconds / totalMs;
            final shrinkStart =
                (_kEntrance + _kHold).inMilliseconds / totalMs;

            final entranceT = (t / entranceEnd).clamp(0.0, 1.0);
            final shrinkT =
                ((t - shrinkStart) / (1 - shrinkStart)).clamp(0.0, 1.0);
            final entranceE = Curves.easeOutQuart.transform(entranceT);
            final shrinkE = Curves.easeOutQuart.transform(shrinkT);

            return Stack(
              key: _stackKey,
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: shrinkE,
                  child: _StatsLayout(
                    stats: widget.stats,
                    slotKey: _slotKey,
                    countDelay: _kEntrance + _kHold,
                  ),
                ),
                _animatedBelt(entranceE, shrinkE, stackW, stackH),
              ],
            );
          },
        );
      },
    );
  }

  Widget _animatedBelt(
    double entranceE,
    double shrinkE,
    double stackW,
    double stackH,
  ) {
    final image = Image(
      image: ThemeImage.image(
        CombatDenSlots.rankBelt,
        fallback: ApiImage.rankAsset(widget.stats.beltAsset),
      ),
      fit: BoxFit.contain,
    );

    // Phase 1/2 (or before slot is measured): big and centered.
    if (shrinkE <= 0 || _slotRect == null) {
      final size = _kBigBelt *
          (_kBeltStartScale + (1 - _kBeltStartScale) * entranceE);
      return Center(
        child: Opacity(
          opacity: entranceE,
          child: SizedBox(width: size, height: size, child: image),
        ),
      );
    }

    // Phase 3: interpolate left/top/width/height from "big and centered"
    // to the measured slot rect. Image stays a single rendered widget.
    final bigLeft = (stackW - _kBigBelt) / 2;
    final bigTop = (stackH - _kBigBelt) / 2;
    final smallLeft = _slotRect!.left;
    final smallTop = _slotRect!.top;
    final smallW = _slotRect!.width;
    final smallH = _slotRect!.height;

    final left = bigLeft + (smallLeft - bigLeft) * shrinkE;
    final top = bigTop + (smallTop - bigTop) * shrinkE;
    final width = _kBigBelt + (smallW - _kBigBelt) * shrinkE;
    final height = _kBigBelt + (smallH - _kBigBelt) * shrinkE;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: image,
    );
  }
}

class _StatsLayout extends StatelessWidget {
  const _StatsLayout({
    required this.stats,
    required this.slotKey,
    required this.countDelay,
  });

  final MockRankStats stats;
  final GlobalKey slotKey;
  final Duration countDelay;

  @override
  Widget build(BuildContext context) {
    final remaining = (stats.classesRequired - stats.classesAttended)
        .clamp(0, stats.classesRequired);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Spacer(),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingBig,
          children: [
            _RankRow(stats: stats, slotKey: slotKey),
            _CountBlock(
              classesAttended: stats.classesAttended,
              countDelay: countDelay,
            ),
          ],
        ),
        const Spacer(),
        Text(
          '$remaining more classes until promotion',
          textAlign: TextAlign.center,
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}

/// Mirrors the profile screen's `RankHeader` row visually, but the belt
/// slot is an empty `SizedBox` keyed for measurement — the actual belt
/// is rendered by the parent's animated overlay so it can fly in from
/// center stage.
class _RankRow extends StatelessWidget {
  const _RankRow({required this.stats, required this.slotKey});

  final MockRankStats stats;
  final GlobalKey slotKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        SizedBox(key: slotKey, width: _kSlotWidth, height: _kSlotHeight),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(stats.rankTitle, style: DesignConstants.h1),
            Text(
              stats.rankSubtitle,
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CountBlock extends StatelessWidget {
  const _CountBlock({
    required this.classesAttended,
    required this.countDelay,
  });

  final int classesAttended;
  final Duration countDelay;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CountUpText(
          target: classesAttended,
          delay: countDelay,
          style: DesignConstants.big1,
          textAlign: TextAlign.center,
        ),
        Text(
          'classes in rank',
          textAlign: TextAlign.center,
          style: DesignConstants.big2,
        ),
      ],
    );
  }
}
