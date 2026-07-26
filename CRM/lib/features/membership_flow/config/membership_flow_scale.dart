import 'package:flutter/material.dart';

import 'package:crm/features/membership_flow/config/admin_flow_scale.dart';
import 'package:crm/features/membership_flow/config/kiosk_flow_scale.dart';

/// The TYPE and MEASURE ramp one membership-flow surface renders at.
///
/// One component set serves two surfaces read at two distances — the
/// front-desk iPad from ~2m and the staff dialog from a desk — so the shared
/// widgets carry no size of their own. Each asks the scale for the ROLE it is
/// rendering ("this is a panel title") and the surface's own scale decides
/// which [DesignConstants] token that resolves to.
///
/// It SELECTS between existing tokens and restates none: no literal size,
/// colour, weight or padding may appear in any scale. A role that wants a
/// value the design system does not have is a missing token, not a number to
/// inline — which is why the desk's own roles were added to
/// `design_constants.dart` (the `flow*` set) rather than written here.
///
/// Every member is a **getter, never a field**, so the token resolves at
/// build time — which is what keeps light/dark live. `DesignConstants`' text
/// styles read `themeController.isDark` on each read, and a scale that
/// snapshotted them in its constructor would freeze the whole flow in
/// whichever mode it happened to be built in.
///
/// It is a TYPE ramp (plus the one measure a surface's form width is set by).
/// Colours, radii, spacing, icon sizes and shadows stay on [DesignConstants]
/// at the call site — none of them changes with the reading distance.
abstract class MembershipFlowScale {
  const MembershipFlowScale();

  /// The kiosk's standing-distance ramp — `DesignConstants`' `kiosk*` set.
  const factory MembershipFlowScale.kiosk() = KioskFlowScale;

  /// The staff dialog's desk ramp — the ADMIN set, plus the handful of `flow*`
  /// roles the admin ramp had no rung for.
  const factory MembershipFlowScale.admin() = AdminFlowScale;

  /// A screen's one anchoring title.
  TextStyle get display;

  /// The one MONEY figure a step is about — the due-today total. Its own role
  /// rather than [display]'s: on the kiosk the amount IS the screen, while at
  /// the desk it sits inside a panel beside a title that out-ranks it.
  TextStyle get total;

  /// The muted line answering a [display] title.
  TextStyle get subtitle;

  /// A big number inside a panel.
  TextStyle get metric;

  /// A panel's own title, one clear step under [display].
  TextStyle get panelTitle;

  /// ONE important sentence set apart.
  TextStyle get statement;

  /// A text input's typed value and its hint.
  TextStyle get fieldText;

  /// A section head inside a screen.
  TextStyle get title;

  /// A name rendered as an identity or a tap target.
  TextStyle get name;

  /// Body copy inside a panel.
  TextStyle get body;

  /// A strong small label.
  TextStyle get label;

  /// The muted line answering a [title] section head.
  TextStyle get sectionText;

  /// A quiet supporting line.
  TextStyle get caption;

  /// The smallest label.
  TextStyle get micro;

  /// A literal value rendered as a mono chip.
  TextStyle get monoValue;

  /// The tracked mono micro-label above the thing it names.
  TextStyle get eyebrow;

  /// A tag pinned on artwork or the tiniest meta line.
  TextStyle get tag;

  /// The loud filled button's label.
  TextStyle get buttonPrimaryLabel;

  /// The secondary outlined button's label.
  TextStyle get buttonOutlineLabel;

  /// The escape tier's label — demoted by weight, never by size.
  TextStyle get buttonGhostLabel;

  /// The loud filled button's box.
  EdgeInsets get buttonPrimaryPadding;

  /// The secondary outlined button's box.
  EdgeInsets get buttonOutlinePadding;

  /// The escape tier's box. Its horizontal value doubles as the optical pull
  /// that lands the ghost's glyph on the step's content rail.
  EdgeInsets get buttonGhostPadding;

  /// The width a step's form panel is capped at (and centred within).
  ///
  /// The only measure here: the width of the whole STAGE belongs to the host's
  /// shell (a full-screen kiosk stage, the desk's dialog), which the scaffold
  /// is handed rather than owning.
  double get formMeasure;
}
