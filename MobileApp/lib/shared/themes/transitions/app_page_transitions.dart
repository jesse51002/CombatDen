import 'package:flutter/material.dart';

import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/core/formats/theme_motion.dart';
import 'package:mobile_app/shared/themes/transitions/card_stack_page_transitions_builder.dart';
import 'package:mobile_app/shared/themes/transitions/fade_page_transitions_builder.dart';
import 'package:mobile_app/shared/themes/transitions/instant_page_transitions_builder.dart';
import 'package:mobile_app/shared/themes/transitions/shared_axis_page_transitions_builder.dart';

/// Resolves `transition_style` into the `PageTransitionsTheme` that
/// `AppTheme.forCanvas()` hands to `MaterialApp`.
///
/// The seam is the theme, not the navigator: every route in
/// `core/app_routes.dart` is pushed by name through `MaterialPageRoute`,
/// which asks `Theme.of(context).pageTransitionsTheme` how to animate.
/// Sitting here means the enum can only change how a route animates —
/// it never sees which route was pushed, never touches the back stack,
/// and cannot turn a `pushReplacementNamed` into a `pushNamed`.
///
/// **Resolution is deferred, not baked.** The theme registers one
/// [_ResolvedPageTransitionsBuilder] per platform, and that builder
/// reads `ThemeMotion.transition()` at the moment a route animates.
/// A `FormatBuilder` would be the wrong tool here: there is no
/// build-time switch to rebuild, and the theme is built in `main.dart`
/// where a rebuild would re-key the whole tree and throw the reviewer
/// back to Home. Reading late means the dev picker's new value is live
/// on the very next navigation with no rebuild at all.
class AppPageTransitions {
  // Private constructor to prevent instantiation
  AppPageTransitions._();

  /// Flutter's own defaults, read from the framework rather than copied
  /// into this file. That is what makes `platformDefault` a genuine
  /// no-op and keeps it one: if the framework changes what a platform
  /// does, this follows, because it is literally the same object.
  static const PageTransitionsTheme _stock = PageTransitionsTheme();

  /// The transition the app would use for [platform] with no
  /// `pageTransitionsTheme` set at all — including the framework's own
  /// fallback for a platform it has no entry for.
  static PageTransitionsBuilder stockBuilderFor(TargetPlatform platform) =>
      _stock.builders[platform] ?? const ZoomPageTransitionsBuilder();

  /// The builder [style] runs on [platform].
  static PageTransitionsBuilder builderFor(
    TransitionStyle style,
    TargetPlatform platform,
  ) => switch (style) {
    TransitionStyle.platformDefault => stockBuilderFor(platform),
    TransitionStyle.fade => const FadePageTransitionsBuilder(),
    TransitionStyle.sharedAxis => const SharedAxisPageTransitionsBuilder(),
    TransitionStyle.cardStack => const CardStackPageTransitionsBuilder(),
    TransitionStyle.none => const InstantPageTransitionsBuilder(),
  };

  /// Every platform is registered, so the framework's own
  /// missing-key fallback never fires and the platform a builder was
  /// registered under is always the platform it is asked about.
  static const Map<TargetPlatform, PageTransitionsBuilder> _builders = {
    TargetPlatform.android: _ResolvedPageTransitionsBuilder(
      TargetPlatform.android,
    ),
    TargetPlatform.iOS: _ResolvedPageTransitionsBuilder(TargetPlatform.iOS),
    TargetPlatform.macOS: _ResolvedPageTransitionsBuilder(TargetPlatform.macOS),
    TargetPlatform.windows: _ResolvedPageTransitionsBuilder(
      TargetPlatform.windows,
    ),
    TargetPlatform.linux: _ResolvedPageTransitionsBuilder(TargetPlatform.linux),
    TargetPlatform.fuchsia: _ResolvedPageTransitionsBuilder(
      TargetPlatform.fuchsia,
    ),
  };

  static const PageTransitionsTheme _theme = PageTransitionsTheme(
    builders: _builders,
  );

  /// The theme `AppTheme.forCanvas()` installs. Const, so two calls
  /// compare equal and a theme rebuild never churns the navigator.
  static PageTransitionsTheme theme() => _theme;
}

/// Delegates to whichever builder the tenant's `transition_style`
/// currently resolves to, for the platform it was registered under.
///
/// Every member forwards, including `transitionDuration` — the route
/// reads that off the theme's builder when it is pushed, so a value
/// whose duration did not forward would animate for the wrong length.
class _ResolvedPageTransitionsBuilder extends PageTransitionsBuilder {
  const _ResolvedPageTransitionsBuilder(this.platform);

  final TargetPlatform platform;

  PageTransitionsBuilder get _active =>
      AppPageTransitions.builderFor(ThemeMotion.transition(), platform);

  @override
  Duration get transitionDuration => _active.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _active.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _active.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _active.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
