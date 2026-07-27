import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';

// Giftbox intro phase durations (file-scoped per CLAUDE.md _k carve-out).
const Duration _kBoxEntrance = Duration(milliseconds: 520);
const Duration _kBoxHold = Duration(milliseconds: 600);
const Duration _kBoxBurst = Duration(milliseconds: 540);
const double _kBoxSize = 220;
const int _kBurstStarCount = 14;

/// Three-phase giftbox intro:
/// 1. Entrance: box flies in with a 3D Y-axis spin + scale + fade.
/// 2. Hold: box at rest, static.
/// 3. Burst: box scales + fades to nothing while ~14 single_point stars
///    explode outward radially from its center to the screen edges.
class GiftboxIntro extends StatefulWidget {
  const GiftboxIntro({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<GiftboxIntro> createState() => _GiftboxIntroState();
}

class _GiftboxIntroState extends State<GiftboxIntro>
    with SingleTickerProviderStateMixin {
  static final List<_BurstStarSeed> _burstSeeds = _buildBurst();

  late final AnimationController _ctrl;

  late final double _entranceEnd =
      _kBoxEntrance.inMilliseconds / _ctrl.duration!.inMilliseconds;
  late final double _burstStart =
      (_kBoxEntrance + _kBoxHold).inMilliseconds /
          _ctrl.duration!.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: _kBoxEntrance + _kBoxHold + _kBoxBurst,
    );
    _ctrl.forward().whenComplete(widget.onComplete);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static List<_BurstStarSeed> _buildBurst() {
    const sizes = [28.0, 36.0, 32.0, 40.0, 26.0, 34.0];
    return [
      for (var i = 0; i < _kBurstStarCount; i++)
        _BurstStarSeed(
          // Even spread around circle, with a small per-star jitter so the
          // burst doesn't read as a perfect ring.
          angle: i / _kBurstStarCount * 2 * math.pi +
              (i.isEven ? 0.12 : -0.12),
          size: sizes[i % sizes.length],
          // Travel reach: most stars go full distance, a few stop short
          // for a layered "near + far" feel.
          reach: i % 4 == 0 ? 0.7 : 1.0,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxRadius = math.min(
              constraints.maxWidth,
              constraints.maxHeight,
            ) /
            2;
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            final entranceT = (t / _entranceEnd).clamp(0.0, 1.0);
            final burstT =
                ((t - _burstStart) / (1 - _burstStart)).clamp(0.0, 1.0);
            return Stack(
              alignment: Alignment.center,
              children: [
                ..._buildBurstStars(burstT, maxRadius),
                _buildBox(entranceT, burstT),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBox(double entranceT, double burstT) {
    final eIn = Curves.easeOutQuart.transform(entranceT);
    final eOut = Curves.easeOutQuart.transform(burstT);
    final scaleIn = 0.5 + 0.5 * eIn;
    final scaleOut = 1.0 - eOut;
    final boxScale = scaleIn * scaleOut;
    final boxOpacity = eIn * (1.0 - eOut);
    // Single Y-axis spin during entrance: starts at 2π, settles to 0.
    final yRotation = (1 - eIn) * 2 * math.pi;

    return Opacity(
      opacity: boxOpacity,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(yRotation)
          ..scaleByDouble(boxScale, boxScale, boxScale, 1),
        child: Image(
          image: ThemeImage.image(
            CombatDenSlots.giftbox,
            fallback: ApiImage.asset('giftbox.png'),
          ),
          width: _kBoxSize,
          height: _kBoxSize,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Iterable<Widget> _buildBurstStars(double burstT, double maxRadius) {
    if (burstT <= 0) return const [];
    return _burstSeeds.map((seed) {
      // Distance: 0 → maxRadius * reach over the burst, eased.
      final dEased = Curves.easeOutQuart.transform(burstT);
      final distance = dEased * maxRadius * seed.reach;
      // Opacity: ramps up quickly (0 → 0.25 burstT), then fades (0.5 → 1).
      final double opacity;
      if (burstT < 0.25) {
        opacity = burstT / 0.25;
      } else if (burstT < 0.5) {
        opacity = 1.0;
      } else {
        opacity = (1 - (burstT - 0.5) / 0.5).clamp(0.0, 1.0);
      }
      // Scale: ramps up to 1 quickly, then maintains.
      final starScale = math.min(1.0, burstT / 0.2);
      final dx = math.cos(seed.angle) * distance;
      final dy = math.sin(seed.angle) * distance;
      return Transform.translate(
        offset: Offset(dx, dy),
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: starScale,
            child: Image(
              image: ThemeImage.image(
                CombatDenSlots.singlePoint,
                fallback: ApiImage.asset('single_point.png'),
              ),
              width: seed.size,
              height: seed.size,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    });
  }
}

class _BurstStarSeed {
  const _BurstStarSeed({
    required this.angle,
    required this.size,
    required this.reach,
  });

  final double angle;
  final double size;
  final double reach;
}
