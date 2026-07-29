import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';

/// The app's ONE pull-to-refresh affordance — a themed [RefreshIndicator]
/// wrapping a tab's scrollable.
///
/// Every tab uses this rather than its own indicator so the spinner's colour,
/// its distance from the top, and (through [AppRefresh]) what a pull actually
/// re-reads can never differ between two tabs of the same app.
///
/// **The child must always accept overscroll.** [RefreshIndicator] can only
/// fire on a scrollable that reports a drag, so whatever scroll view sits
/// below this needs `physics: const AlwaysScrollableScrollPhysics()` — without
/// it a page shorter than the viewport (an empty rewards catalog, a gym with
/// no videos, a rank-less profile) silently refuses the pull.
class AppRefreshView extends StatelessWidget {
  const AppRefreshView({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  /// The pull's work. Must not resolve before the work does — the spinner
  /// tracks this future.
  final Future<void> Function() onRefresh;

  /// The scrollable, with always-scrollable physics.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: DesignConstants.primaryColor,
      backgroundColor: DesignConstants.backgroundColor,
      child: child,
    );
  }
}
