import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The glyph for a KPI tile, by tile key. An unknown key falls back to a
/// generic chart glyph rather than going iconless, so a new backend metric
/// still renders complete.
const Map<String, IconData> kKpiIcons = {
  'total_members': Symbols.group_sharp,
  'new_members': Symbols.person_add_sharp,
  'lost_members': Symbols.person_remove_sharp,
  'trial_members': Symbols.schedule_sharp,
  'mrr': Symbols.payments_sharp,
  'collected': Symbols.account_balance_wallet_sharp,
  'refunds': Symbols.undo_sharp,
  'failed_payments': Symbols.credit_card_off_sharp,
  'avg_per_member': Symbols.person_sharp,
  'discounts_given': Symbols.sell_sharp,
  'outstanding': Symbols.pending_actions_sharp,
  'checkins': Symbols.how_to_reg_sharp,
  'avg_visits': Symbols.directions_run_sharp,
  'no_show_rate': Symbols.event_busy_sharp,
  'active_trials': Symbols.hourglass_top_sharp,
  'conversion': Symbols.trending_up_sharp,
  'churn': Symbols.trending_down_sharp,
  'retention_90d': Symbols.verified_sharp,
  'streaks': Symbols.local_fire_department_sharp,
  'promotions': Symbols.military_tech_sharp,
  'points_redeemed': Symbols.redeem_sharp,
  'video_ctr': Symbols.play_circle_sharp,
};

IconData kpiIconFor(String key) => kKpiIcons[key] ?? Symbols.bar_chart_sharp;

/// Tiles where a RISE is bad news. Everything else reads up as good.
///
/// The delta badge's tone comes from this, never from the sign alone: churn
/// climbing 11% is not a win.
const Set<String> kUpIsBadKpis = {
  'lost_members',
  'churn',
  'no_show_rate',
  'refunds',
  'failed_payments',
  'outstanding',
  'discounts_given',
  'at_risk_members',
};

/// Whether a move of [delta] on tile [key] is good, bad, or neither.
///
/// Returns null for a flat (or absent) move, which renders no badge at all.
bool? isGoodMove(String key, double? delta) {
  if (delta == null || delta == 0) return null;
  final up = delta > 0;
  return kUpIsBadKpis.contains(key) ? !up : up;
}
