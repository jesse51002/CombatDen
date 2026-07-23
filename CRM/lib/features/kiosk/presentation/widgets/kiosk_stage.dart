import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The centered, max-width content stage every kiosk sub-screen sits in —
/// mirrors the mockup `.stage` (centered column capped at a content width, on
/// the kiosk ground). Scrolls when the content is taller than the viewport so
/// nothing is ever clipped on a short iPad fold; otherwise [center] decides
/// whether the content sits centered (result screens) or top-aligned (home /
/// class pick).
class KioskStage extends StatelessWidget {
  final Widget child;
  final bool center;

  const KioskStage({super.key, required this.child, this.center = false});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: center ? Alignment.center : Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignConstants.navMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignConstants.paddingBig,
                    vertical: DesignConstants.paddingBig,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
