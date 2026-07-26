import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/membership_flow/discounts/custom_discount_form_value.dart';

/// The custom-discount form's RULES, with no tree pumped.
///
/// The one that matters is the lifetime: the backend accepts a duration span
/// **XOR** an explicit `end_date` and the database refuses both together
/// (`chk_discount_value_lifetime_exclusive`). Assembling a value with both
/// would be rejected at the money step — after staff have said a number out
/// loud — so the exclusivity is asserted on the way OUT of the form.
void main() {
  group('amount validation', () {
    test('nothing typed says what to type', () {
      expect(
        validateFlowDiscountAmount('', FlowDiscountAmountKind.percentage),
        'Enter an amount',
      );
      expect(
        validateFlowDiscountAmount('   ', FlowDiscountAmountKind.dollar),
        'Enter an amount',
      );
      expect(
        validateFlowDiscountAmount('half', FlowDiscountAmountKind.percentage),
        'Enter an amount',
      );
    });

    test('a percent states its RANGE, not just that it is wrong', () {
      expect(
        validateFlowDiscountAmount('0', FlowDiscountAmountKind.percentage),
        'Percent must be 1–100',
      );
      expect(
        validateFlowDiscountAmount('101', FlowDiscountAmountKind.percentage),
        'Percent must be 1–100',
      );
      expect(
        validateFlowDiscountAmount('-5', FlowDiscountAmountKind.percentage),
        'Percent must be 1–100',
      );
    });

    test('a whole 100% is legal — a comp is a real sale', () {
      expect(
        validateFlowDiscountAmount('100', FlowDiscountAmountKind.percentage),
        isNull,
      );
      expect(
        validateFlowDiscountAmount('12.5', FlowDiscountAmountKind.percentage),
        isNull,
      );
    });

    test('a dollar amount only has to be above zero', () {
      expect(
        validateFlowDiscountAmount('0', FlowDiscountAmountKind.dollar),
        'Amount must be above 0',
      );
      expect(
        validateFlowDiscountAmount('250', FlowDiscountAmountKind.dollar),
        isNull,
        reason: 'a \$250 discount is not a percent and has no ceiling here',
      );
    });
  });

  group('span validation', () {
    test('a missing or non-positive count says what a count is', () {
      expect(validateFlowDiscountSpan(''), 'Enter a number above 0');
      expect(validateFlowDiscountSpan('0'), 'Enter a number above 0');
      expect(validateFlowDiscountSpan('-2'), 'Enter a number above 0');
      expect(validateFlowDiscountSpan('two'), 'Enter a number above 0');
    });

    test('a positive whole count passes', () {
      expect(validateFlowDiscountSpan('3'), isNull);
    });
  });

  group('the lifetime is a span XOR an end date, never both', () {
    test('forever sends neither', () {
      final value = buildFlowDiscountValue(
        kind: FlowDiscountAmountKind.percentage,
        amount: 20,
        lifetime: FlowDiscountLifetime.forever,
        spanText: '3',
        endDate: DateTime.utc(2026, 11, 30),
      );
      expect(value.percentageOff, 20);
      expect(value.dollarOff, isNull);
      expect(value.durationAmount, isNull);
      expect(value.durationUnit, isNull);
      expect(value.endDate, isNull);
    });

    test('a span sends the count and its unit, and NO end date', () {
      final value = buildFlowDiscountValue(
        kind: FlowDiscountAmountKind.percentage,
        amount: 12.5,
        lifetime: FlowDiscountLifetime.cycles,
        spanText: '3',
        endDate: DateTime.utc(2026, 11, 30),
      );
      expect(value.durationAmount, 3);
      expect(value.durationUnit, DiscountDurationUnit.cycle);
      expect(
        value.endDate,
        isNull,
        reason: 'the database refuses a value carrying both',
      );
    });

    test('every span lifetime maps to its backend unit', () {
      expect(
        flowLifetimeUnit(FlowDiscountLifetime.cycles),
        DiscountDurationUnit.cycle,
      );
      expect(
        flowLifetimeUnit(FlowDiscountLifetime.days),
        DiscountDurationUnit.day,
      );
      expect(
        flowLifetimeUnit(FlowDiscountLifetime.weeks),
        DiscountDurationUnit.week,
      );
      expect(
        flowLifetimeUnit(FlowDiscountLifetime.months),
        DiscountDurationUnit.month,
      );
      expect(flowLifetimeUnit(FlowDiscountLifetime.forever), isNull);
      expect(flowLifetimeUnit(FlowDiscountLifetime.untilDate), isNull);
    });

    test('an END DATE sends the date, and NO span — the new capability', () {
      final value = buildFlowDiscountValue(
        kind: FlowDiscountAmountKind.dollar,
        amount: 15,
        lifetime: FlowDiscountLifetime.untilDate,
        spanText: '3',
        endDate: DateTime.utc(2026, 11, 30),
      );
      expect(value.dollarOff, 1500, reason: 'dollars go on the wire as cents');
      expect(value.percentageOff, isNull);
      expect(value.durationAmount, isNull);
      expect(value.durationUnit, isNull);
      expect(value.endDate, DateTime.utc(2026, 11, 30));
    });

    test('the end date reaches the wire as a date-only ISO string', () {
      final value = buildFlowDiscountValue(
        kind: FlowDiscountAmountKind.percentage,
        amount: 20,
        lifetime: FlowDiscountLifetime.untilDate,
        endDate: DateTime.utc(2026, 11, 30),
      );
      expect(value.toJson()['end_date'], '2026-11-30');
    });

    test('only a span lifetime asks for a count', () {
      expect(flowLifetimeNeedsSpan(FlowDiscountLifetime.forever), isFalse);
      expect(flowLifetimeNeedsSpan(FlowDiscountLifetime.untilDate), isFalse);
      for (final lifetime in [
        FlowDiscountLifetime.cycles,
        FlowDiscountLifetime.days,
        FlowDiscountLifetime.weeks,
        FlowDiscountLifetime.months,
      ]) {
        expect(flowLifetimeNeedsSpan(lifetime), isTrue);
      }
    });
  });

  test('a percent and a dollar are exclusive too', () {
    final percent = buildFlowDiscountValue(
      kind: FlowDiscountAmountKind.percentage,
      amount: 20,
      lifetime: FlowDiscountLifetime.forever,
    );
    expect(percent.percentageOff, 20);
    expect(percent.dollarOff, isNull);

    final dollars = buildFlowDiscountValue(
      kind: FlowDiscountAmountKind.dollar,
      amount: 20,
      lifetime: FlowDiscountLifetime.forever,
    );
    expect(dollars.dollarOff, 2000);
    expect(dollars.percentageOff, isNull);
  });
}
