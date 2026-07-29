import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/formats/dev/format_panel.dart';

/// Horizontal-padding variant for [AppScreenScaffold].
enum AppScreenHorizontalPadding {
  /// `DesignConstants.screenHorizontalPadding` (16). The default.
  standard,

  /// `DesignConstants.paddingBig` (32). Used by inset-frame screens like
  /// the photo verification flow.
  big,

  /// No horizontal padding — the screen renders edge-to-edge and any
  /// internal padding is the caller's responsibility.
  none,
}

/// Single source of truth for screen-level chrome: background color,
/// safe-area, optional fixed topbar, optional fixed bottom nav, and the
/// horizontal-padding inset that the body content should sit inside.
class AppScreenScaffold extends StatelessWidget {
  const AppScreenScaffold({
    super.key,
    required this.child,
    this.topbar,
    this.bottomNav,
    this.horizontalPadding = AppScreenHorizontalPadding.standard,
    this.backgroundColor,
  });

  final Widget child;
  final Widget? topbar;
  final Widget? bottomNav;
  final AppScreenHorizontalPadding horizontalPadding;
  final Color? backgroundColor;

  bool get hasTopNav => topbar != null;
  bool get hasBottomNav => bottomNav != null;

  double get _horizontalInset {
    switch (horizontalPadding) {
      case AppScreenHorizontalPadding.standard:
        return DesignConstants.screenHorizontalPadding;
      case AppScreenHorizontalPadding.big:
        return DesignConstants.paddingBig;
      case AppScreenHorizontalPadding.none:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = horizontalPadding == AppScreenHorizontalPadding.none
        ? child
        : Padding(
            padding: EdgeInsets.symmetric(horizontal: _horizontalInset),
            child: child,
          );

    return Scaffold(
      backgroundColor: backgroundColor ?? DesignConstants.backgroundColor,
      // The format picker. Opened ONLY by its own handle: both screen
      // edges belong to Android's system back gesture, so an edge drag
      // never reaches the app. Debug builds only — `kDebugMode` is a
      // const, so the panel and its imports are tree-shaken out of a
      // release build and cannot ship to a tenant.
      endDrawer: kDebugMode ? const FormatPanel() : null,
      endDrawerEnableOpenDragGesture: false,
      // The handle lives INSIDE the Scaffold: it calls `Scaffold.of`,
      // which only sees an ancestor Scaffold, so a sibling would find
      // nothing and the control would silently do nothing.
      body: Stack(
        children: [
          SafeArea(
            top: !hasTopNav,
            bottom: !hasBottomNav,
            child: Column(
              children: [
                if (hasTopNav) topbar!,
                Expanded(child: body),
                if (hasBottomNav) bottomNav!,
              ],
            ),
          ),
          if (kDebugMode) const _FormatHandle(),
        ],
      ),
    );
  }
}

/// The dev-only grab handle for the format picker.
///
/// A deliberate on-screen control rather than a gesture: on Android 10+
/// both screen edges are the system back gesture, so an edge drag never
/// reaches the app, and long-press / double-tap are already spoken for
/// by the schedule and the topbar. Low opacity and right-aligned so it
/// stays out of a screenshot's way. Debug builds only.
class _FormatHandle extends StatelessWidget {
  const _FormatHandle();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: Center(
        child: Builder(
          builder: (context) => Opacity(
            opacity: 0.55,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Scaffold.of(context).openEndDrawer(),
              child: Container(
                width: 26,
                height: 64,
                decoration: BoxDecoration(
                  color: DesignConstants.primaryColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(DesignConstants.radiusBig),
                    bottomLeft: Radius.circular(DesignConstants.radiusBig),
                  ),
                ),
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Center(
                    child: Text(
                      'FMT',
                      style: DesignConstants.pSmall.copyWith(
                        color: DesignConstants.primaryButtonText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
