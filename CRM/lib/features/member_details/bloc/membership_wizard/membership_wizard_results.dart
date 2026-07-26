/// What a landed start MEANS — the three-way split, and the fold that keeps a
/// retry's receipt honest.
///
/// Pure, because both are money statements: an outcome read one notch too
/// optimistically tells a payer their membership started when it did not, and
/// a receipt that forgets what an earlier attempt created reads as though half
/// the family's money went nowhere.
library;

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_outcome.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';

/// Which of the three a landed start is, or null when nothing has landed (or
/// the response carried nothing to itemise, which is not an outcome anybody
/// can be told about).
///
/// `unknown` is neither created nor failed and falls out of BOTH extremes: a
/// response holding one is a [MembershipWizardOutcome.partial], never
/// "all created" (the backend would not confirm it) and never "all failed"
/// (the money may have moved).
MembershipWizardOutcome? outcomeOf(MemberMembershipsStartResponse? result) {
  final items = result?.results ?? const [];
  if (items.isEmpty) return null;
  if (items.every((item) => item.isCreated)) {
    return MembershipWizardOutcome.allCreated;
  }
  if (items.every((item) => item.isFailed)) {
    return MembershipWizardOutcome.allFailed;
  }
  return MembershipWizardOutcome.partial;
}

/// Fold a retry's response into the one it retried, so the breakdown keeps
/// every membership THIS RUN produced rather than only the last attempt's.
///
/// A retry re-sends only what the previous start did not create, so without
/// the fold a partial that then succeeded would print a one-row receipt and
/// omit the membership that landed first. The newer outcome always REPLACES
/// the older for the same (member, plan), which is what keeps
/// [retryScopeFor] over the fold equal to the latest response's un-created set
/// instead of letting a stale row keep offering a retry.
MemberMembershipsStartResponse mergeStartResults(
  MemberMembershipsStartResponse? previous,
  MemberMembershipsStartResponse landed,
) {
  if (previous == null || previous.results.isEmpty) return landed;
  final replaced = {for (final item in landed.results) resultKey(item)};
  return MemberMembershipsStartResponse(
    chargeCount: landed.chargeCount,
    multipleCharges: landed.multipleCharges,
    results: [
      for (final item in previous.results)
        if (!replaced.contains(resultKey(item))) item,
      ...landed.results,
    ],
  );
}
