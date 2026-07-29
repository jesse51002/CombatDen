import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_frame.dart';

// Reference extent the sizes below were tuned against; render scale is
// `extent / _kReferenceExtent` so a larger stage scales proportionally.
// File-scoped per CLAUDE.md's `_k` carve-out for layout math.
const double _kReferenceExtent = 280;
const double _kEdgePad = 28;
const double _kParticleSize = 30;
const double _kHeroSize = 120;
// Just enough Z to make a quarter turn read as a turn and not a squash.
const double _kPerspective = 0.0012;
// A trail is vertical: almost no horizontal smear.
const double _kTrailAspect = 0.2;
const double _kBlurEpsilon = 0.05;

/// The one widget that paints a [CelebrationIntroFrame].
///
/// Every value renders through here, which is what makes the invariant
/// mechanical: there is exactly one hero and one particle field in the
/// tree no matter which value is active, so no value can introduce a
/// second sparkle surface or drop the figure.
class CelebrationIntroFigure extends StatelessWidget {
  const CelebrationIntroFigure({
    super.key,
    required this.spec,
    required this.frame,
    required this.hero,
    required this.particle,
  });

  final CelebrationIntroSpec spec;
  final CelebrationIntroFrame frame;
  final ImageProvider hero;
  final ImageProvider particle;

  /// Marks the hero figure so the invariants gate can assert every
  /// playing value actually renders one.
  static const Key heroKey = Key('celebration-intro-hero');

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final smallerExtent = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final renderScale = smallerExtent / _kReferenceExtent;
        final particleSize = _kParticleSize * renderScale;
        final heroSize = _kHeroSize * renderScale;
        final maxRadius =
            smallerExtent / 2 - _kEdgePad - particleSize / 2;

        return Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < spec.particleRadii.length; i++)
              _particle(i, maxRadius, particleSize),
            _hero(heroSize, constraints.maxHeight / 2, renderScale),
          ],
        );
      },
    );
  }

  Widget _particle(int i, double maxRadius, double size) {
    final count = spec.particleRadii.length;
    final theta = frame.particleSpin + i * 2 * math.pi / count;
    final radius = maxRadius * frame.particleSpread * spec.particleRadii[i];
    return Transform.translate(
      offset: Offset(math.cos(theta) * radius, math.sin(theta) * radius),
      child: Opacity(
        opacity: frame.particleOpacity.clamp(0.0, 1.0),
        child: Image(
          image: particle,
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _hero(double size, double riseSpan, double renderScale) {
    Widget figure = Image(
      key: heroKey,
      image: hero,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );

    if (frame.heroBlur > _kBlurEpsilon) {
      final sigma = frame.heroBlur * renderScale;
      figure = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: sigma * _kTrailAspect,
          sigmaY: sigma,
          tileMode: ui.TileMode.decal,
        ),
        child: figure,
      );
    }

    figure = Opacity(
      opacity: frame.heroOpacity.clamp(0.0, 1.0),
      child: Transform.scale(scale: frame.heroScale, child: figure),
    );

    if (frame.heroFlip != 0) {
      figure = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, _kPerspective)
          ..rotateY(frame.heroFlip),
        child: figure,
      );
    }

    if (frame.heroRise != 0) {
      figure = Transform.translate(
        offset: Offset(0, frame.heroRise * riseSpan),
        child: figure,
      );
    }

    return figure;
  }
}
