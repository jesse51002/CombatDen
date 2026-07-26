import 'package:flutter/widgets.dart';

import 'package:crm/features/membership_flow/config/kiosk_flow_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// The kiosk's own [KioskFlowCopy], for the step heads only THIS surface has.
///
/// The lane's fork, its duplicate confirms, its "who's paying" pick and its
/// authorized-payer run are screens the desk never walks, so their words sit
/// on the kiosk's copy class rather than on the shared `MembershipFlowCopy` —
/// an abstract method the desk could only answer with an invented sentence is
/// worse than no method at all. Reading them needs the CONCRETE type, hence
/// this one cast.
///
/// It stays a cast rather than a `const KioskFlowCopy()` at the call site on
/// purpose: the surface's voice arrives from the one `MembershipFlowTheme` the
/// host mounts, and a step that constructed its own would be a second source
/// of copy — free to drift from the one every shared component below it reads.
///
/// One helper, one file: a widget that only needs a SHARED line still calls
/// `MembershipFlowTheme.copyOf(context)` directly and never comes through
/// here.
KioskFlowCopy kioskStepCopy(BuildContext context) =>
    MembershipFlowTheme.copyOf(context) as KioskFlowCopy;
