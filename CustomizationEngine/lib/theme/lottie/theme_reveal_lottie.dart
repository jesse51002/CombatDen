import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'package:customization_engine/theme/lottie/scale_reveal.dart';
import 'package:customization_engine/theme/lottie/theme_lottie.dart';

/// A reveal-type lottie: plays a reveal-capable animation and composites
/// [revealedImage] at the preset's `insertion_point` the moment the
/// timeline reaches its frame.
///
/// [revealedImage] is any image-getter widget — typically an `Image` whose
/// provider is `ThemeImage.image(slot, fallback: ...)`, so it already
/// resolves its own override + bundled fallback. ThemeRevealLottie never fetches
/// the image; it only positions and times the reveal, so the caller's
/// widget keeps owning its image resolution.
///
/// The recolour + bundled-fallback behaviour is delegated to
/// `ThemeLottie`. ThemeRevealLottie adds the composite-at-frame the base
/// widget doesn't do. When [slot] has no override insertion_point (the
/// bundled-fallback / no-backend case) the reveal timing and position fall
/// back to the caller's [fallbackRevealAt] + [fallbackX]/[fallbackY]/
/// [fallbackWidth]/[fallbackHeight], which default to a centred 60% box
/// revealed at the end of the animation. A preset's insertion_point always
/// wins over these. It expands to fill its parent, so give it bounded
/// constraints (wrap in a `SizedBox`, `Expanded`, `AspectRatio`, …) — it
/// lays its layers out in an expanded `Stack`.
class ThemeRevealLottie extends StatefulWidget {
  const ThemeRevealLottie({
    super.key,
    required this.slot,
    required this.fallbackAsset,
    required this.revealedImage,
    this.fallbackRevealAt = 1.0,
    this.fallbackX = 0.2,
    this.fallbackY = 0.2,
    this.fallbackWidth = 0.6,
    this.fallbackHeight = 0.6,
    this.onComplete,
    this.fit = BoxFit.contain,
  });

  /// Customization slot id of the reveal lottie (see `CombatDenSlots`).
  final String slot;

  /// Bundled `.json` played when [slot] has no override.
  final String fallbackAsset;

  /// The image to reveal — an object that already knows how to get itself
  /// (e.g. `Image(image: ThemeImage.image(slot, fallback: ...))`).
  final Widget revealedImage;

  /// Point on the timeline (0..1) at which the image pops in when there is
  /// NO override insertion_point (the bundled-fallback / no-backend case).
  /// A preset's insertion_point frame always wins over this. Defaults to
  /// the end; set it to e.g. 0.75 to keep a mid-animation reveal on
  /// fallback.
  final double fallbackRevealAt;

  /// Normalised reveal rect (0..1, top-left origin) used to position the
  /// image when there is NO override insertion_point. A preset's
  /// insertion_point geometry always wins over these. Defaults describe a
  /// centred box at 60% of the animation bounds.
  final double fallbackX;
  final double fallbackY;
  final double fallbackWidth;
  final double fallbackHeight;

  /// Fired once when the animation finishes, so the caller can transition
  /// (e.g. to a stats screen). Never fires more than once.
  final VoidCallback? onComplete;

  final BoxFit fit;

  @override
  State<ThemeRevealLottie> createState() => _ThemeRevealLottieState();
}

class _ThemeRevealLottieState extends State<ThemeRevealLottie>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this);
  bool _revealed = false;
  bool _completed = false;

  /// Point on the timeline (0..1) at which the image pops in. Starts at the
  /// caller's [ThemeRevealLottie.fallbackRevealAt] (the fallback timing) and
  /// is overridden by the preset's insertion_point once the lottie loads.
  late double _revealAt = widget.fallbackRevealAt;

  @override
  void initState() {
    super.initState();
    _ctrl
      ..addListener(_onTick)
      ..addStatusListener(_onStatus);
  }

  void _onTick() {
    if (_revealed || !mounted) return;
    if (_ctrl.value >= _revealAt) {
      setState(() => _revealed = true);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (_completed || status != AnimationStatus.completed) return;
    _completed = true;
    widget.onComplete?.call();
  }

  void _onLoaded(LottieComposition composition) {
    final insertion = ThemeLottie.resolve(widget.slot)?.insertionPoint;
    if (insertion != null && composition.durationFrames > 0) {
      final raw =
          (insertion.frame - composition.startFrame) /
          composition.durationFrames;
      _revealAt = raw.clamp(0.0, 1.0);
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
    // Position: the preset's insertion_point geometry wins; otherwise the
    // caller's normalised fallback rect (default centred 60%).
    final insertion = ThemeLottie.resolve(widget.slot)?.insertionPoint;
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ThemeLottie(
            slot: widget.slot,
            fallbackAsset: widget.fallbackAsset,
            controller: _ctrl,
            fit: widget.fit,
            onLoaded: _onLoaded,
          ),
          if (_revealed)
            _PlacedReveal(
              x: insertion?.x ?? widget.fallbackX,
              y: insertion?.y ?? widget.fallbackY,
              width: insertion?.width ?? widget.fallbackWidth,
              height: insertion?.height ?? widget.fallbackHeight,
              child: ScaleReveal(child: widget.revealedImage),
            ),
        ],
      ),
    );
  }
}

/// Positions [child] inside the animation box at the given normalised rect
/// ([x]/[y]/[width]/[height], 0..1, top-left origin).
class _PlacedReveal extends StatelessWidget {
  const _PlacedReveal({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.child,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: [
            Positioned(
              left: x * w,
              top: y * h,
              width: width * w,
              height: height * h,
              child: child,
            ),
          ],
        );
      },
    );
  }
}
