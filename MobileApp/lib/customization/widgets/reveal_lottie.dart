import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'package:mobile_app/customization/brand_lottie.dart';
import 'package:mobile_app/customization/data/models/lottie_override.dart';
import 'package:mobile_app/shared/widgets/animation/scale_reveal.dart';
import 'package:mobile_app/customization/widgets/branded_lottie.dart';

/// A reveal-type lottie: plays a reveal-capable animation and composites
/// [revealedImage] at the preset's `insertion_point` the moment the
/// timeline reaches its frame.
///
/// [revealedImage] is any image-getter widget — typically a `BrandedImage`
/// that already knows how to resolve its own override + bundled fallback.
/// RevealLottie never fetches the image; it only positions and times the
/// reveal, so the caller's widget keeps owning its image resolution.
///
/// The recolour + bundled-fallback behaviour is delegated to
/// `BrandedLottie`. RevealLottie adds the composite-at-frame the standalone
/// widget doesn't do. With no override (or a fallback `.json` that carries
/// no insertion geometry) the image reveals centred once the animation
/// completes. Give it a bounded size (wrap in a `SizedBox` or pass
/// [width]/[height]) — it lays its layers out in an expanded `Stack`.
class RevealLottie extends StatefulWidget {
  const RevealLottie({
    super.key,
    required this.slot,
    required this.fallbackAsset,
    required this.revealedImage,
    this.revealProgress = 1.0,
    this.onComplete,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  /// Customization slot id of the reveal lottie (see `CombatDenSlots`).
  final String slot;

  /// Bundled `.json` played when [slot] has no override.
  final String fallbackAsset;

  /// The image to reveal — an object that already knows how to get itself
  /// (e.g. `BrandedImage(slot: ..., fallback: ...)`).
  final Widget revealedImage;

  /// Timeline progress (0..1) at which the image pops in when there is NO
  /// override insertion_point (the bundled-fallback / no-backend case).
  /// An override's insertion_point always wins over this. Defaults to the
  /// end; set it to e.g. 0.75 to keep a mid-animation reveal on fallback.
  final double revealProgress;

  /// Fired once when the animation finishes, so the caller can transition
  /// (e.g. to a stats screen). Never fires more than once.
  final VoidCallback? onComplete;

  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  State<RevealLottie> createState() => _RevealLottieState();
}

class _RevealLottieState extends State<RevealLottie>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this);
  bool _revealed = false;
  bool _completed = false;

  /// Timeline progress (0..1) at which the image pops in. Starts at the
  /// caller's [RevealLottie.revealProgress] (the fallback timing) and is
  /// overridden by the preset's insertion_point once the lottie loads.
  late double _revealProgress = widget.revealProgress;

  @override
  void initState() {
    super.initState();
    _ctrl
      ..addListener(_onTick)
      ..addStatusListener(_onStatus);
  }

  void _onTick() {
    if (_revealed || !mounted) return;
    if (_ctrl.value >= _revealProgress) {
      setState(() => _revealed = true);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (_completed || status != AnimationStatus.completed) return;
    _completed = true;
    widget.onComplete?.call();
  }

  void _onLoaded(LottieComposition composition) {
    final insertion = BrandLottie.of(widget.slot)?.insertionPoint;
    if (insertion != null && composition.durationFrames > 0) {
      final raw =
          (insertion.frame - composition.startFrame) /
          composition.durationFrames;
      _revealProgress = raw.clamp(0.0, 1.0);
    }
    _ctrl
      ..duration = composition.duration
      ..forward();
  }

  @override
  void dispose() {
    _ctrl
      ..removeListener(_onTick)
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insertion = BrandLottie.of(widget.slot)?.insertionPoint;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BrandedLottie(
            slot: widget.slot,
            fallbackAsset: widget.fallbackAsset,
            controller: _ctrl,
            fit: widget.fit,
            onLoaded: _onLoaded,
          ),
          if (_revealed)
            _PlacedReveal(
              insertion: insertion,
              child: ScaleReveal(child: widget.revealedImage),
            ),
        ],
      ),
    );
  }
}

/// Positions [child] inside the animation box. With an [insertion] point it
/// honours the normalised anchor + size (top-left origin, 0..1); without
/// one it centres the child at 60% of the box (the fallback case).
class _PlacedReveal extends StatelessWidget {
  const _PlacedReveal({required this.insertion, required this.child});

  final LottieInsertionPoint? insertion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final point = insertion;
    if (point == null) {
      return Center(
        child: FractionallySizedBox(
          widthFactor: 0.6,
          heightFactor: 0.6,
          child: child,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: [
            Positioned(
              left: point.x * w,
              top: point.y * h,
              width: point.width * w,
              height: point.height * h,
              child: child,
            ),
          ],
        );
      },
    );
  }
}
