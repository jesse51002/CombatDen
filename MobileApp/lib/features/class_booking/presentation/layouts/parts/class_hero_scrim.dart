import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

const double _kScrimHeight = 180;

/// A fade from the page background down over the top of the class
/// photo, so the topbar stays legible on the arrangements that lay it
/// over the image.
///
/// Keyed to `backgroundColor` rather than to a literal black: a light
/// preset fades to its own canvas, and the text tokens keep the
/// contrast they were picked for.
class ClassHeroScrim extends StatelessWidget {
  const ClassHeroScrim({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kScrimHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              DesignConstants.backgroundColor.withValues(alpha: 0.92),
              DesignConstants.backgroundColor.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
