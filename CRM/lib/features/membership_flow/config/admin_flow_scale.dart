import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';

/// The desk's ramp: the staff dialog is read from a desk at arm's length, so
/// almost every role resolves to the app's OWN admin ladder (`h1` / `big2` /
/// `h2` / `h3` / `p` / `pSmall`) and the flow reads as part of the CRM rather
/// than as a kiosk shrunk down.
///
/// Only the roles the admin ladder has no rung for resolve to the `flow*`
/// tokens added for this surface — a picked membership's statement line
/// ([statement]), a person's name ([name]), and the three button tiers, whose
/// dialog scale sits between the kiosk's and `AppPrimaryButton`'s defaults.
///
/// Reached through `MembershipFlowScale.admin()`.
class AdminFlowScale extends MembershipFlowScale {
  const AdminFlowScale();

  /// A step's title inside the dialog. `h1` and not `big2`: the dialog already
  /// carries a context bar naming what it is, so the step head is a heading,
  /// not a hero.
  @override
  TextStyle get display => DesignConstants.h1;

  /// The due-today total, which is the biggest thing on the review — it
  /// out-ranks the step title deliberately, because the number is what staff
  /// read back to the person paying.
  @override
  TextStyle get total => DesignConstants.big2;

  @override
  TextStyle get subtitle => DesignConstants.pBig;

  /// A plan card's price. Level with the step title: on a grid of cards the
  /// price is the fact being compared.
  @override
  TextStyle get metric => DesignConstants.h1;

  @override
  TextStyle get panelTitle => DesignConstants.h2;

  @override
  TextStyle get statement => DesignConstants.flowStatement;

  @override
  TextStyle get fieldText => DesignConstants.pBig;

  @override
  TextStyle get title => DesignConstants.h2;

  @override
  TextStyle get name => DesignConstants.flowName;

  @override
  TextStyle get body => DesignConstants.pBig;

  @override
  TextStyle get label => DesignConstants.h3;

  @override
  TextStyle get sectionText => DesignConstants.p;

  @override
  TextStyle get caption => DesignConstants.p;

  @override
  TextStyle get micro => DesignConstants.pSmall;

  /// The app has exactly ONE mono token, so a mono literal at the desk renders
  /// in the same tracked face an eyebrow does. Adding a second mono size for a
  /// role no desk surface renders yet would be a token invented ahead of its
  /// call site.
  @override
  TextStyle get monoValue => DesignConstants.eyebrow;

  @override
  TextStyle get eyebrow => DesignConstants.eyebrow;

  @override
  TextStyle get tag => DesignConstants.tag;

  /// The primary and the outline share one label size — the two tiers differ
  /// by fill and box, never by type.
  @override
  TextStyle get buttonPrimaryLabel => DesignConstants.flowButtonLabel;

  @override
  TextStyle get buttonOutlineLabel => DesignConstants.flowButtonLabel;

  @override
  TextStyle get buttonGhostLabel => DesignConstants.flowButtonGhostLabel;

  @override
  EdgeInsets get buttonPrimaryPadding =>
      DesignConstants.flowButtonPrimaryPadding;

  @override
  EdgeInsets get buttonOutlinePadding =>
      DesignConstants.flowButtonOutlinePadding;

  @override
  EdgeInsets get buttonGhostPadding => DesignConstants.flowButtonGhostPadding;

  @override
  double get formMeasure => DesignConstants.flowFormMeasure;
}
