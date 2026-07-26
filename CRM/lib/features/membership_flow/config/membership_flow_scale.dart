import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The TYPE and MEASURE ramp one membership-flow surface renders at.
///
/// One component set serves two surfaces read at two distances — the
/// front-desk iPad from ~2m and the staff dialog from a desk — so the shared
/// widgets carry no size of their own. Each asks the scale for the ROLE it is
/// rendering ("this is a panel title") and the surface's own scale decides
/// which [DesignConstants] token that resolves to.
///
/// It SELECTS between existing tokens and restates none: no literal size,
/// colour, weight or padding may appear in this file. A role that wants a
/// value the design system does not have is a missing token, not a number to
/// inline here.
///
/// Every member is a **getter, never a field**, so the token resolves at
/// build time — which is what keeps light/dark live. `DesignConstants`' text
/// styles read `themeController.isDark` on each read, and a scale that
/// snapshotted them in its constructor would freeze the whole flow in
/// whichever mode it happened to be built in.
///
/// It is a TYPE ramp (plus the two measures a surface's width is set by).
/// Colours, radii, spacing, icon sizes and shadows stay on [DesignConstants]
/// at the call site — none of them changes with the reading distance.
abstract class MembershipFlowScale {
  const MembershipFlowScale();

  /// The kiosk's standing-distance ramp — `DesignConstants`' `kiosk*` set.
  const factory MembershipFlowScale.kiosk() = _KioskFlowScale;

  /// A screen's one anchoring title.
  TextStyle get display;

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
  double get formMeasure;

  /// The width the whole content stage is capped at.
  double get stageMeasure;
}

/// The kiosk's ramp: every role resolves to its `kiosk*` token, and the two
/// tail roles to the unprefixed shared ones (they measure the same at both
/// distances, so there is nothing for the kiosk to step up to).
class _KioskFlowScale extends MembershipFlowScale {
  const _KioskFlowScale();

  @override
  TextStyle get display => DesignConstants.kioskDisplay;

  @override
  TextStyle get subtitle => DesignConstants.kioskSubtitle;

  @override
  TextStyle get metric => DesignConstants.kioskMetric;

  @override
  TextStyle get panelTitle => DesignConstants.kioskPanelTitle;

  @override
  TextStyle get statement => DesignConstants.kioskStatement;

  @override
  TextStyle get fieldText => DesignConstants.kioskFieldText;

  @override
  TextStyle get title => DesignConstants.kioskTitle;

  @override
  TextStyle get name => DesignConstants.kioskName;

  @override
  TextStyle get body => DesignConstants.kioskBody;

  @override
  TextStyle get label => DesignConstants.kioskLabel;

  @override
  TextStyle get sectionText => DesignConstants.kioskSectionText;

  @override
  TextStyle get caption => DesignConstants.kioskCaption;

  @override
  TextStyle get micro => DesignConstants.kioskMicro;

  @override
  TextStyle get monoValue => DesignConstants.kioskMonoValue;

  @override
  TextStyle get eyebrow => DesignConstants.eyebrow;

  @override
  TextStyle get tag => DesignConstants.tag;

  @override
  TextStyle get buttonPrimaryLabel => DesignConstants.kioskButtonPrimaryLabel;

  @override
  TextStyle get buttonOutlineLabel => DesignConstants.kioskButtonOutlineLabel;

  @override
  TextStyle get buttonGhostLabel => DesignConstants.kioskButtonGhostLabel;

  @override
  EdgeInsets get buttonPrimaryPadding =>
      DesignConstants.kioskButtonPrimaryPadding;

  @override
  EdgeInsets get buttonOutlinePadding =>
      DesignConstants.kioskButtonOutlinePadding;

  @override
  EdgeInsets get buttonGhostPadding => DesignConstants.kioskButtonGhostPadding;

  @override
  double get formMeasure => DesignConstants.kioskFormMeasure;

  @override
  double get stageMeasure => DesignConstants.navMaxWidth;
}
