import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The centered, max-width content stage every kiosk sub-screen sits in — a
/// centered column capped at a content width, on the kiosk ground. Scrolls
/// when the content is taller than the viewport so nothing is ever clipped on
/// a short iPad fold; otherwise [center] decides whether the content sits
/// centered (result screens) or top-aligned (home / class pick).
///
/// A [footer] is PINNED to the bottom of the fold while the content scrolls
/// beneath it. That is the whole point for the escape hatch: a way out that a
/// tall class grid can push below the fold is not a way out. Without a
/// footer the stage keeps its plain scroll-the-whole-thing behaviour, so no
/// existing screen changes.
class KioskStage extends StatelessWidget {
  final Widget child;
  final bool center;

  /// Pinned to the bottom of the stage, inside the same content rail — the
  /// escape foot on an in-progress flow. Ignores [center] (a pinned foot has
  /// nothing to center against).
  final Widget? footer;

  const KioskStage({
    super.key,
    required this.child,
    this.center = false,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final foot = footer;
    if (foot != null) return _Railed(child: _Pinned(footer: foot, body: child));
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: _Railed(
              center: center,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// The stage's content rail: centered, capped at the content width, padded.
class _Railed extends StatelessWidget {
  final Widget child;
  final bool center;

  const _Railed({required this.child, this.center = false});

  @override
  Widget build(BuildContext context) {
    return Align(
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
    );
  }
}

/// A scrolling body under a footer held on the fold.
class _Pinned extends StatelessWidget {
  final Widget body;
  final Widget footer;

  const _Pinned({required this.body, required this.footer});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(child: SingleChildScrollView(child: body)),
        footer,
      ],
    );
  }
}
