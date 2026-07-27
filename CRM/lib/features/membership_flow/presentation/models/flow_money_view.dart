import 'package:equatable/equatable.dart';

/// What a purchase surface states about money: the one figure coming off the
/// card today, its parts, and what happens after today.
///
/// Every amount is in MINOR UNITS and is formatted only at render, and every
/// one of them comes straight off the server's preview — nothing here is
/// derived from a plan row. The host does the reading; this carries the answer.
class FlowMoneyView extends Equatable {
  /// The one combined amount charged today.
  final int dueTodayMinorUnits;

  /// The ISO code every figure below is rendered in.
  final String currency;

  /// The itemisation, so the one big number is visibly its parts.
  final List<FlowMoneyLine> lines;

  /// Today's charge is a PART period — a mid-cycle join pays the rest of it.
  final bool prorated;

  /// The billing-period end that part period runs up to. Null when the preview
  /// names none.
  final DateTime? prorationUntil;

  /// The payer's statement will show TWO charges today.
  final bool chargedTwiceToday;

  final String? cardBrand;
  final String? cardLast4;

  /// What bills again after today, or null on a purely one-time cart — which
  /// is what stops a one-off pack implying it recurs.
  final FlowRecurringView? recurring;

  const FlowMoneyView({
    required this.dueTodayMinorUnits,
    required this.currency,
    this.lines = const [],
    this.prorated = false,
    this.prorationUntil,
    this.chargedTwiceToday = false,
    this.cardBrand,
    this.cardLast4,
    this.recurring,
  });

  @override
  List<Object?> get props => [
        dueTodayMinorUnits,
        currency,
        lines,
        prorated,
        prorationUntil,
        chargedTwiceToday,
        cardBrand,
        cardLast4,
        recurring,
      ];
}

/// One itemised charge: the words that name it and the invoice line's own
/// amount. Only the LABEL is derived by the host — never the money.
class FlowMoneyLine extends Equatable {
  final String label;
  final int amountMinorUnits;

  const FlowMoneyLine({required this.label, required this.amountMinorUnits});

  @override
  List<Object?> get props => [label, amountMinorUnits];
}

/// What happens after today — the per-cycle amount, the cycle it bills on, and
/// the date it first bills.
class FlowRecurringView extends Equatable {
  final int totalMinorUnits;

  /// The plan's own billing unit as a word — "month", "2 months", "week" — so
  /// "each month" is never asserted about a weekly or yearly plan.
  final String cycleWord;

  final DateTime? nextPaymentAt;

  /// The first names this recurring charge is for. Empty says nothing about
  /// who: in a group the names matter, since a one-off pack does not recur for
  /// the child who got it.
  final List<String> names;

  const FlowRecurringView({
    required this.totalMinorUnits,
    required this.cycleWord,
    this.nextPaymentAt,
    this.names = const [],
  });

  @override
  List<Object?> get props => [
        totalMinorUnits,
        cycleWord,
        nextPaymentAt,
        names,
      ];
}
