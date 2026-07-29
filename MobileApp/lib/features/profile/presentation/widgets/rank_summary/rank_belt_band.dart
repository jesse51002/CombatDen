import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The belt hero band's height, and the strength of the scrim that
/// keeps the rank names legible over whatever art the tenant ships.
const double _kBandHeight = 220;
const double _kScrimTopAlpha = 0.35;

/// The belt as a full-width band with [names] over its foot.
///
/// The scrim is what makes this safe for a white-label tenant: the belt
/// art is theirs, so the names cannot rely on it being dark enough.
class RankBeltBand extends StatelessWidget {
  const RankBeltBand({super.key, required this.belt, required this.names});

  final ImageProvider belt;
  final Widget names;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kBandHeight,
      child: Stack(
        children: [
          Positioned.fill(child: Image(image: belt, fit: BoxFit.cover)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    DesignConstants.backgroundColor.withValues(
                      alpha: _kScrimTopAlpha,
                    ),
                    DesignConstants.backgroundColor,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: DesignConstants.paddingBig,
            right: DesignConstants.paddingBig,
            bottom: DesignConstants.spacingLarge,
            child: names,
          ),
        ],
      ),
    );
  }
}
