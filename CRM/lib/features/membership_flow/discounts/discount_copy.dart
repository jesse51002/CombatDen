/// Every word the inline discount surface says.
///
/// **Staff-only** — see `discount_labels.dart` for why nothing under
/// `discounts/` may reach the kiosk.
///
/// Plain constants rather than another implementation of `MembershipFlowCopy`,
/// and that is the whole point of the capability model: this surface exists on
/// ONE side of the flow, so there is no second voice for it to drift from. The
/// shared component set carries no literal precisely because it renders twice;
/// these render once.
///
/// The voice matches `StaffFlowCopy` — third person, addressed to somebody
/// selling on a member's behalf.
abstract final class FlowDiscountCopy {
  /// The dashed affordance at the end of a membership's chip row.
  static const String addDiscount = 'Add discount';

  /// The panel's two sources.
  static const String presetsTab = 'Gym discounts';
  static const String customTab = 'Custom';

  /// Close the panel. It commits nothing — each pick already applied when it
  /// was made — so it says "done", not "save".
  static const String closePanel = 'Done';

  /// The inert mark on a preset already on this membership.
  static const String added = 'Added';

  /// Why the list is shorter than the discounts page, and how stacking works.
  /// Stated rather than left to be discovered from a total that looks wrong.
  static const String presetsFootnote =
      'One-off customs built for another membership are not offered as '
      'presets — build one for this membership on the Custom tab. Discounts '
      'stack: percentages apply in order, then each fixed amount comes off '
      'once per line.';

  /// The gym has saved no presets. The custom form is still right there, so
  /// the empty state names it instead of dead-ending.
  static const String noPresetsTitle = 'This gym has no discount presets.';
  static const String noPresetsBody =
      'Save one under Memberships → Discounts to reuse it, or build a '
      'one-off for this membership on the Custom tab.';

  /// The custom form's own labels.
  static const String amountKindLabel = 'What comes off';
  static const String amountLabel = 'Amount';
  static const String percentHint = '1 – 100';
  static const String lifetimeLabel = 'How long it lasts';
  static const String lifetimeNote = 'Applies to every bill until it ends';
  static const String spanLabel = 'How many';
  static const String cyclesLabel = 'How many cycles';
  static const String endDateLabel = 'Last day it applies';

  /// Said once, up front, so a form that has not turned red yet is not read as
  /// a form that has nothing to say.
  static const String validationNote =
      'Nothing is checked until you add it — the form won\'t turn red while '
      'you type.';

  static const String cancel = 'Cancel';
  static const String add = 'Add discount';

  /// What removing a chip does, for a screen reader. It names the membership
  /// scope: the same preset is usually on several cards at once, and removing
  /// it here leaves the others alone.
  static String removeSemantic(String label) =>
      'Remove $label from this membership';

  /// The live reading under an end date — the cutoff is inclusive, and the
  /// bill after it is the full price again.
  static String endDateNote(String day) =>
      'Comes off every bill up to $day. The full price resumes on the next '
      'one.';
}
