import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';

/// The kiosk's ramp: every role resolves to its `kiosk*` token, and the two
/// eyebrow/tag roles to the unprefixed shared ones (they measure the same at
/// both distances, so there is nothing for the kiosk to step up to).
///
/// Reached through `MembershipFlowScale.kiosk()` — the factory is the name
/// hosts and tests use.
class KioskFlowScale extends MembershipFlowScale {
  const KioskFlowScale();

  @override
  TextStyle get display => DesignConstants.kioskDisplay;

  /// The due-today total IS the kiosk's screen at that moment, so it takes the
  /// same token the screen title does.
  @override
  TextStyle get total => DesignConstants.kioskDisplay;

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
  double get formMeasure => DesignConstants.flowFormMeasure;
}
