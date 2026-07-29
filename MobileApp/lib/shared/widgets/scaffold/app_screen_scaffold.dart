import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

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
      body: SafeArea(
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
    );
  }
}
