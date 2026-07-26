import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_money_labels.dart';

/// The plan block's member-facing words — the ONE place a
/// [KioskPlanBlockReason] becomes a sentence, mirroring
/// `kiosk_signup_stop_copy.dart`. Every switch is exhaustive on purpose, so a
/// new reason can never ship without words, and every line is blame-free.
///
/// One reason NAMES the plan and the other deliberately does not; that
/// inversion is the rule, not style drift. [KioskPlanBlockReason.trialUsed] is
/// per MEMBER — one trial closes every trial plan on the grid — so naming a
/// plan would state a narrower rule than the grid enforces, while
/// [KioskPlanBlockReason.alreadyOnPlan] is per PLAN (the backend conflicts on
/// `plan_id = ANY(:plan_ids)`), so naming it is exact.

/// The popup's title — what happened, in the member's own terms.
String kioskPlanBlockTitle(KioskPlanBlockReason reason) {
  return switch (reason) {
    KioskPlanBlockReason.trialUsed => 'You\'ve already had a trial',
    KioskPlanBlockReason.alreadyOnPlan => 'You already have this membership',
  };
}

/// The popup's body. The plan step is walked once per training person, so in a
/// GROUP it NAMES whoever it is about — an unnamed block in a run of named
/// turns is ambiguous exactly when it matters most. A blank first name
/// degrades to "they", never to a stand-in name.
String kioskPlanBlockBody(
  KioskSignupState state,
  KioskPlanBlockReason reason,
) {
  final first = state.activePerson.firstName.trim();
  return switch (reason) {
    KioskPlanBlockReason.trialUsed => _trialBody(state.isGroup, first),
    KioskPlanBlockReason.alreadyOnPlan =>
      _heldBody(state.isGroup, first, state.heldPlanNames),
  };
}

/// The warm disc's glyph. `card_membership_sharp` names the OBJECT the member
/// holds; `history_sharp` ("this already happened") is right for a spent trial
/// and wrong for one they hold now. Never a tick — on a plan card a tick reads
/// as *selected*, the one thing these popups must not look like.
IconData kioskPlanBlockGlyph(KioskPlanBlockReason reason) {
  return switch (reason) {
    KioskPlanBlockReason.trialUsed => Symbols.history_sharp,
    KioskPlanBlockReason.alreadyOnPlan => Symbols.card_membership_sharp,
  };
}

String _trialBody(bool isGroup, String firstName) {
  const tail = 'Everything else on the list is open — or the coach at the '
      'desk can talk through the options.';
  if (!isGroup) {
    return 'Trials are one to a member, and you\'ve already had yours. $tail';
  }
  if (firstName.isEmpty) {
    return 'Trials are one to a member, and they\'ve already had theirs. '
        '$tail';
  }
  return 'Trials are one to a member, and $firstName has already had theirs. '
      '$tail';
}

/// The held-plan body — the plan is NAMED, because the rule is per plan. With
/// no name resolvable at all (a held plan the gym no longer offers) it falls
/// back to the unnamed form rather than printing a blank.
String _heldBody(bool isGroup, String firstName, List<String> planNames) {
  final plans = flowNameList(planNames);
  const soloTail = 'Anything else on the list is open — or the coach at the '
      'desk can change your plan.';
  const groupTail = 'Anything else on the list is open — or the coach at the '
      'desk can change the plan.';
  if (plans.isEmpty) {
    return isGroup
        ? 'They already have that membership, so there\'s nothing to buy '
            'again. $groupTail'
        : 'You already have that membership, so there\'s nothing to buy '
            'again. $soloTail';
  }
  if (!isGroup) {
    return 'You\'re on $plans right now, so there\'s nothing to buy again. '
        '$soloTail';
  }
  if (firstName.isEmpty) {
    return 'They\'re on $plans right now, so there\'s nothing to buy again. '
        '$groupTail';
  }
  return '$firstName is on $plans right now, so there\'s nothing to buy '
      'again. $groupTail';
}

/// The tag pinned over a blocked plan card's hero. "Already used" is right for
/// a spent trial and wrong for a live membership — they have not used it up,
/// they HAVE it.
String kioskPlanBlockTag(KioskPlanBlockReason reason) {
  return switch (reason) {
    KioskPlanBlockReason.trialUsed => 'Already used',
    KioskPlanBlockReason.alreadyOnPlan => 'You have this',
  };
}

/// The plan step's inline notice — the membership the ACTIVE person already
/// holds, stated before they start picking so the marked card has an answer
/// above it rather than only behind a tap. Self-gating: nothing held returns
/// null, so a brand-new member never sees it.
///
/// Privacy: it names the PLAN of a recurring membership and NOTHING else — no
/// price, no date, no status word ("frozen" is billing state, printed in a
/// lobby), no one-time or trial pack (those stack, so naming them is
/// disclosure with no purchasing consequence), and never another member's
/// memberships — the names come off `state.activePerson`, which makes a
/// cross-person leak unrepresentable.
String? kioskHeldPlanNotice(KioskSignupState state) {
  final names = state.heldPlanNames;
  if (names.isEmpty) return null;
  final plans = flowNameList(names);
  final marked = names.length == 1
      ? 'It\'s marked below so you don\'t buy it twice.'
      : 'They\'re marked below so you don\'t buy them twice.';
  if (!state.isGroup) return 'You\'re on $plans right now. $marked';
  final first = state.activePerson.firstName.trim();
  if (first.isEmpty) return 'They\'re on $plans right now. $marked';
  return '$first is on $plans right now. $marked';
}
