import 'package:flutter/widgets.dart';

import 'package:crm/features/membership_flow/config/flow_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';

/// Hands the surface's [MembershipFlowScale] and [MembershipFlowCopy] to every
/// shared flow widget beneath it. The host mounts exactly one, above the step
/// switcher, and nothing below it ever names a surface: a widget asks for the
/// scale and the copy, and renders whatever it is handed.
///
/// The two travel TOGETHER on purpose. They answer the same question about the
/// same surface — how big, and in whose voice — and a host that could mount one
/// without the other would be a host that renders desk words at kiosk size.
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

  /// Every user-facing word the components below render.
  final MembershipFlowCopy copy;

  const MembershipFlowTheme({
    super.key,
    required this.scale,
    required this.copy,
    required super.child,
  });

  /// The SCALE in force — [copyOf] is its wording counterpart, and a component
  /// that renders text usually reads both.
  ///
  /// Asserts rather than falling back: a silent default would let a host that
  /// forgot to mount one render a whole surface at the other surface's size,
  /// which is exactly the drift this module exists to make impossible.
  static MembershipFlowScale of(BuildContext context) => _read(context).scale;

  /// The WORDS in force. Same contract as [of]: no fallback, because a default
  /// voice is how a member-facing screen ends up phrased for staff.
  static MembershipFlowCopy copyOf(BuildContext context) =>
      _read(context).copy;

  static MembershipFlowTheme _read(BuildContext context) {
    final theme =
        context.dependOnInheritedWidgetOfExactType<MembershipFlowTheme>();
    assert(
      theme != null,
      'No MembershipFlowTheme found above this widget. A membership-flow '
      'host mounts one (with its own MembershipFlowScale and '
      'MembershipFlowCopy) above the step switcher; a widget test pumping a '
      'flow widget on its own must wrap it in the same way.',
    );
    return theme!;
  }

  @override
  bool updateShouldNotify(MembershipFlowTheme oldWidget) =>
      oldWidget.scale != scale || oldWidget.copy != copy;
}
