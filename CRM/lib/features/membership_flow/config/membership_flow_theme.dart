import 'package:flutter/widgets.dart';

import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';

/// Hands the surface's [MembershipFlowScale] to every shared flow widget
/// beneath it. The host mounts exactly one, above the step switcher, and
/// nothing below it ever names a surface: a widget asks for the scale and
/// renders whatever it is handed.
///
/// Deliberately an `InheritedWidget` and **not** a `ThemeExtension`. This app
/// never reads `Theme.of(context)` — `DesignConstants` is the driver and
/// `AppTheme.current` reflects it rather than the reverse (see `CRM/CLAUDE.md`
/// *Theming System*) — so routing the flow's scale through Material's theme
/// would introduce the one lookup the app is built to avoid.
///
/// It carries no theme-mode plumbing of its own: the scale's members are
/// getters, so a light/dark switch repaints through the existing
/// `themeController` rebuild without this widget changing at all.
class MembershipFlowTheme extends InheritedWidget {
  final MembershipFlowScale scale;

  const MembershipFlowTheme({
    super.key,
    required this.scale,
    required super.child,
  });

  /// The scale in force. Asserts rather than falling back: a silent default
  /// would let a host that forgot to mount one render a whole surface at the
  /// other surface's size, which is exactly the drift this module exists to
  /// make impossible.
  static MembershipFlowScale of(BuildContext context) {
    final theme =
        context.dependOnInheritedWidgetOfExactType<MembershipFlowTheme>();
    assert(
      theme != null,
      'No MembershipFlowTheme found above this widget. A membership-flow '
      'host mounts one (with its own MembershipFlowScale) above the step '
      'switcher; a widget test pumping a flow widget on its own must wrap it '
      'in the same way.',
    );
    return theme!.scale;
  }

  @override
  bool updateShouldNotify(MembershipFlowTheme oldWidget) =>
      oldWidget.scale != scale;
}
