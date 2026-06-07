import 'package:flutter/material.dart';
import 'package:crm/showcase/showcase_tokens.dart';

/// Horizontal-padding variant — clone of MobileApp's
/// `AppScreenHorizontalPadding`.
enum ShowcasePadding { standard, big, none }

/// Clone of MobileApp's `AppScreenScaffold`: background, safe-area, optional
/// fixed topbar + bottom nav, and the horizontal inset for the body. Used so
/// the showcase screens carry the exact member-app chrome.
class ShowcaseScaffold extends StatelessWidget {
  const ShowcaseScaffold({
    super.key,
    required this.child,
    this.topbar,
    this.bottomNav,
    this.horizontalPadding = ShowcasePadding.standard,
    this.backgroundColor,
  });

  final Widget child;
  final Widget? topbar;
  final Widget? bottomNav;
  final ShowcasePadding horizontalPadding;
  final Color? backgroundColor;

  bool get hasTopNav => topbar != null;
  bool get hasBottomNav => bottomNav != null;

  double get _horizontalInset {
    switch (horizontalPadding) {
      case ShowcasePadding.standard:
        return ShowcaseTokens.screenHorizontalPadding;
      case ShowcasePadding.big:
        return ShowcaseTokens.paddingBig;
      case ShowcasePadding.none:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = horizontalPadding == ShowcasePadding.none
        ? child
        : Padding(
            padding: EdgeInsets.symmetric(horizontal: _horizontalInset),
            child: child,
          );

    return Scaffold(
      backgroundColor: backgroundColor ?? ShowcaseTokens.backgroundColor,
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
