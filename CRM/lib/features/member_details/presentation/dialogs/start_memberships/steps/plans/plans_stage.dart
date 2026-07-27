import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';

/// Which of the plans step's five screens is on.
///
/// One value rather than a chain of booleans read twice, because the body and
/// the footer must always agree about which screen is up — a footer stating a
/// reason the body has stopped showing is the failure this replaces.
enum PlansStage {
  /// The catalogue read has not come back yet.
  loading,

  /// It failed, and says so with a retry.
  failed,

  /// It landed empty: no plan at this gym carries an active price.
  noPlans,

  /// Every pick was taken back off, so the run has nobody left to price.
  nobody,

  /// The ordinary screen — the catalogue, over this person's picks.
  grid,
}

PlansStage plansStageOf(
  MembershipWizardState state,
  MembershipWizardPerson? person,
) {
  if (state.plansLoad.isFailed) return PlansStage.failed;
  // Idle counts as loading: the catalogue is fetched when the run opens, so a
  // read that has not started yet is one that has not answered yet either.
  if (state.plans.isEmpty && !state.plansLoad.isReady) {
    return PlansStage.loading;
  }
  if (state.plans.isEmpty) return PlansStage.noPlans;
  if (person == null) return PlansStage.nobody;
  return PlansStage.grid;
}
