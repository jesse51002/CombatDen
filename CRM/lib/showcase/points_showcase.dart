import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:crm/showcase/celebrations/showcase_celebration_stats.dart';
import 'package:crm/showcase/showcase_assets.dart';
import 'package:crm/showcase/showcase_slots.dart';
import 'package:crm/showcase/showcase_tokens.dart';
import 'package:crm/showcase/support/count_up_text.dart';
import 'package:crm/showcase/support/showcase_scaffold.dart';
import 'package:crm/showcase/support/staggered_reveal.dart';
import 'package:theme_flutter/theme/animation/celebration_timings.dart';
import 'package:theme_flutter/theme/theme_image.dart';

// Per-screen layout/timing math — clone of MobileApp's points_body _k consts.
const Duration _kSphereDuration = Duration(milliseconds: 1700);
const double _kSpinTurns = 1.4;
const double _kConvergeStart = 0.74;
const int _kStarCount = 14;
const double _kGoldenAngle = 2.39996;
// Reference extent the seed star sizes were tuned against. Render scale is
// `extent / _kReferenceExtent` so larger screens get proportionally larger
// stars without re-tuning the seed table.
const double _kReferenceExtent = 280;
const double _kHeroSize = 238;

// How long the focused points content holds before the sphere replays.
const Duration _kPointsHold = Duration(milliseconds: 2600);

/// Exact visual clone of the member app's post-class **points celebration**
/// (`PointsScreen` / `PointsBody`): a swarm of 3D `single_point` stars
/// distributed on a sphere fills the body, spins, then collapses inward to
/// nothing — and the focused stat illustration with a "+N points" count-up
/// and the all-time total caption cascade in. Loops.
class PointsShowcase extends StatefulWidget {
  const PointsShowcase({super.key, this.loop = true, this.onCycleComplete});

  final bool loop;
  final VoidCallback? onCycleComplete;

  @override
  State<PointsShowcase> createState() => _PointsShowcaseState();
}

class _PointsShowcaseState extends State<PointsShowcase> {
  bool _showPoints = false;
  int _cycle = 0; // re-keying the sphere rebuilds + restarts it
  Timer? _hold;

  void _onSphereDone() {
    if (!mounted || _showPoints) return;
    setState(() => _showPoints = true);
    _hold = Timer(_kPointsHold, _restart);
  }

  void _restart() {
    if (!mounted) return;
    widget.onCycleComplete?.call();
    if (!widget.loop) return;
    setState(() {
      _showPoints = false;
      _cycle++;
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const stats = showcasePointsStats;
    return ShowcaseScaffold(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: ShowcaseTokens.spacingBig,
        ),
        child: _showPoints
            ? SizedBox.expand(
                child: Column(
                  key: ValueKey(_cycle),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(),
                    const _FocusedContent(stats: stats),
                    const Spacer(),
                    _TotalCaption(total: stats.totalPoints),
                  ],
                ),
              )
            : SizedBox.expand(
                child: _PointSphere(
                  key: ValueKey(_cycle),
                  onComplete: _onSphereDone,
                ),
              ),
      ),
    );
  }
}

class _FocusedContent extends StatelessWidget {
  const _FocusedContent({required this.stats});

  final ShowcasePointsStats stats;

  @override
  Widget build(BuildContext context) {
    return StaggeredReveal(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: ShowcaseTokens.spacingLarge,
        children: [
          Image(
            image: ThemeImage.image(
              ShowcaseSlots.pointsStarsImage,
              fallback: ShowcaseAsset.image('stat_points_stars.png'),
            ),
            width: _kHeroSize,
            height: _kHeroSize,
            fit: BoxFit.contain,
          ),
          CountUpText(
            target: stats.gained,
            prefix: '+',
            suffix: ' points',
            style: ShowcaseTokens.big2,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TotalCaption extends StatelessWidget {
  const _TotalCaption({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return StaggeredReveal(
      delay: CelebrationTimings.countUpDuration +
          CelebrationTimings.revealStagger,
      child: Text(
        '${_formatThousands(total)} total points',
        textAlign: TextAlign.center,
        style: ShowcaseTokens.h3.copyWith(
          color: ShowcaseTokens.text2nd,
        ),
      ),
    );
  }
}

/// Stars distributed on a unit sphere via Fibonacci spiral, then projected
/// to 2D each frame with a Y-axis spin and (during the final beat) a radial
/// collapse to the center. Fills its parent's bounds via `LayoutBuilder`.
class _PointSphere extends StatefulWidget {
  const _PointSphere({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<_PointSphere> createState() => _PointSphereState();
}

class _PointSphereState extends State<_PointSphere>
    with SingleTickerProviderStateMixin {
  static final List<_StarSeed> _seeds = _buildSphere();

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _kSphereDuration);
    _ctrl.forward().whenComplete(widget.onComplete);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static List<_StarSeed> _buildSphere() {
    const sizes = [28.0, 36.0, 32.0, 40.0, 30.0];
    return [
      for (var i = 0; i < _kStarCount; i++)
        () {
          final y = 1 - 2 * (i + 0.5) / _kStarCount;
          final r = math.sqrt(1 - y * y);
          final theta = i * _kGoldenAngle;
          return _StarSeed(
            x: r * math.cos(theta),
            y: y,
            z: r * math.sin(theta),
            size: sizes[i % sizes.length],
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Star sizes scale by the smaller dimension so they don't get
        // gigantic on tall screens — but the orbital path uses each axis
        // independently so the ellipsoid stretches to fill width AND height.
        final smallerExtent =
            math.min(constraints.maxWidth, constraints.maxHeight);
        final renderScale = smallerExtent / _kReferenceExtent;
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            final spin = t * 2 * math.pi * _kSpinTurns;
            final converge =
                ((t - _kConvergeStart) / (1 - _kConvergeStart))
                    .clamp(0.0, 1.0);
            final easedConverge = Curves.easeInQuart.transform(converge);
            final edgePad = 28 * renderScale;
            final radiusX =
                (constraints.maxWidth / 2 - edgePad) * (1 - easedConverge);
            final radiusY =
                (constraints.maxHeight / 2 - edgePad) * (1 - easedConverge);

            final cosA = math.cos(spin);
            final sinA = math.sin(spin);
            final projected = [
              for (var i = 0; i < _seeds.length; i++)
                _ProjectedStar(
                  seed: _seeds[i],
                  x: _seeds[i].x * cosA + _seeds[i].z * sinA,
                  z: -_seeds[i].x * sinA + _seeds[i].z * cosA,
                ),
            ]..sort((a, b) => a.z.compareTo(b.z));

            return Stack(
              alignment: Alignment.center,
              children: [
                for (final p in projected)
                  _renderStar(
                    p,
                    radiusX,
                    radiusY,
                    easedConverge,
                    renderScale,
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _renderStar(
    _ProjectedStar p,
    double radiusX,
    double radiusY,
    double converge,
    double renderScale,
  ) {
    final depth = (p.z + 1) / 2; // 0 (back) → 1 (front)
    final scale = (1 - converge) * (0.55 + 0.45 * depth);
    final opacity = (1 - converge) * (0.4 + 0.6 * depth);
    return Transform.translate(
      offset: Offset(p.x * radiusX, -p.seed.y * radiusY),
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Image(
            image: ThemeImage.image(
              ShowcaseSlots.singlePoint,
              fallback: ShowcaseAsset.image('single_point.png'),
            ),
            width: p.seed.size * renderScale,
            height: p.seed.size * renderScale,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _StarSeed {
  const _StarSeed({
    required this.x,
    required this.y,
    required this.z,
    required this.size,
  });

  final double x;
  final double y;
  final double z;
  final double size;
}

class _ProjectedStar {
  const _ProjectedStar({required this.seed, required this.x, required this.z});

  final _StarSeed seed;
  final double x;
  final double z;
}

String _formatThousands(int n) {
  if (n < 1000) return '$n';
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
