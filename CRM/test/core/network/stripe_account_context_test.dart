import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/network/stripe_account_context.dart';
import 'package:crm/core/state/selected_gym.dart';

void main() {
  group('StripeAccountContext.apply', () {
    test('applies a connected account and enables payments', () async {
      final applied = <String?>[];
      final ctx = StripeAccountContext()
        ..applyToStripe = (id) async => applied.add(id);

      await ctx.apply('acct_iron');

      // The connected account was pushed to Stripe.js and card entry is enabled.
      expect(applied, ['acct_iron']);
      expect(ctx.appliedAccountId, 'acct_iron');
      expect(ctx.isReady, isTrue);
      expect(ctx.paymentsAvailable, isTrue);
    });

    test('a null (not-onboarded) account blocks card entry, fail closed',
        () async {
      final applied = <String?>[];
      final ctx = StripeAccountContext()
        ..applyToStripe = (id) async => applied.add(id);

      await ctx.apply(null);

      // Resolved, but no account → payments unavailable, so CardFieldBox never
      // mounts a field that would tokenize onto the platform account.
      expect(applied, [null]);
      expect(ctx.appliedAccountId, isNull);
      expect(ctx.isReady, isTrue);
      expect(ctx.paymentsAvailable, isFalse);
    });

    test('an empty account string is treated as no account', () async {
      final ctx = StripeAccountContext()..applyToStripe = (_) async {};
      await ctx.apply('');
      expect(ctx.appliedAccountId, isNull);
      expect(ctx.paymentsAvailable, isFalse);
    });

    test('re-applies on a gym switch (different account)', () async {
      final applied = <String?>[];
      final ctx = StripeAccountContext()
        ..applyToStripe = (id) async => applied.add(id);

      await ctx.apply('acct_a');
      await ctx.apply('acct_b');

      // The switch re-applied so the new gym's account is the one Stripe.js uses.
      expect(applied, ['acct_a', 'acct_b']);
      expect(ctx.appliedAccountId, 'acct_b');
      expect(ctx.paymentsAvailable, isTrue);
    });

    test('re-applying the SAME account is a no-op (never rebinds the field)',
        () async {
      var calls = 0;
      final ctx = StripeAccountContext()
        ..applyToStripe = (_) async => calls++;

      await ctx.apply('acct_a');
      await ctx.apply('acct_a');

      // Re-creating the JS Stripe object under a mounted CardField throws, so an
      // unchanged account must not re-apply.
      expect(calls, 1);
    });

    test('a Stripe failure fails closed and does not throw', () async {
      final ctx = StripeAccountContext()
        ..applyToStripe = (_) async => throw StateError('stripe down');

      // Never throws — a failure must not crash the caller (setActiveGym).
      await ctx.apply('acct_a');

      expect(ctx.isReady, isTrue);
      expect(ctx.paymentsAvailable, isFalse); // fail closed
      expect(ctx.appliedAccountId, isNull);
      expect(ctx.error, isA<StateError>());
    });

    test('retries after a failure (same account) instead of no-op', () async {
      var attempt = 0;
      final ctx = StripeAccountContext()
        ..applyToStripe = (_) async {
          attempt++;
          if (attempt == 1) throw StateError('transient');
        };

      await ctx.apply('acct_a'); // fails
      await ctx.apply('acct_a'); // must retry, not short-circuit

      expect(attempt, 2);
      expect(ctx.paymentsAvailable, isTrue);
      expect(ctx.appliedAccountId, 'acct_a');
    });
  });

  group('StripeAccountContext closes both gates while applying', () {
    test('both are false for the DURATION of the first apply', () async {
      final gate = Completer<void>();
      final ctx = StripeAccountContext()..applyToStripe = (_) => gate.future;

      final pending = ctx.apply('acct_iron');

      // Closed SYNCHRONOUSLY, before the first await — nobody awaits `apply`
      // (SelectedGym.setActiveGym fires it), so this window is exactly what a
      // CardFieldBox mounting right after a gym activation observes.
      expect(ctx.isReady, isFalse);
      expect(ctx.paymentsAvailable, isFalse);

      gate.complete();
      await pending;

      expect(ctx.isReady, isTrue);
      expect(ctx.paymentsAvailable, isTrue);
    });

    test('a gym switch closes them until the NEW account is live', () async {
      var gate = Completer<void>()..complete();
      final ctx = StripeAccountContext()..applyToStripe = (_) => gate.future;

      await ctx.apply('acct_a');
      expect(ctx.isReady, isTrue);
      expect(ctx.paymentsAvailable, isTrue);

      gate = Completer<void>();
      final pending = ctx.apply('acct_b');

      // THE bug this closes: while acct_b was still being applied, both flags
      // held acct_a's `true`, so a card field could mount against the OUTGOING
      // gym's JS Stripe object — cards are tokenized on the gym's connected
      // account, so a card entered for gym B would land on gym A's account.
      expect(ctx.isReady, isFalse);
      expect(ctx.paymentsAvailable, isFalse);
      // ...and the field must not be told "unavailable" either: CardFieldBox
      // tests isReady FIRST, so a closed gate reads as the spinner.
      expect(ctx.appliedAccountId, 'acct_a');

      gate.complete();
      await pending;

      expect(ctx.appliedAccountId, 'acct_b');
      expect(ctx.isReady, isTrue);
      expect(ctx.paymentsAvailable, isTrue);
    });

    test('the close notifies listeners, so a mounted field tears down',
        () async {
      final gate = Completer<void>();
      final ctx = StripeAccountContext()..applyToStripe = (_) => gate.future;
      var notifications = 0;
      ctx.addListener(() => notifications++);

      final pending = ctx.apply('acct_a');
      // One notification for the close, before Stripe has been touched.
      expect(notifications, 1);

      gate.complete();
      await pending;
      // And one for the resolve, which remounts the field on the new account.
      expect(notifications, 2);
    });

    test('a redundant same-account apply does NOT close them', () async {
      final ctx = StripeAccountContext()..applyToStripe = (_) async {};
      await ctx.apply('acct_a');
      var notifications = 0;
      ctx.addListener(() => notifications++);

      await ctx.apply('acct_a');

      // The idempotent early return runs above the close, so a live CardField
      // is never flickered — re-creating the JS Stripe object under a mounted
      // field is what throws "the Element belongs to a different instance".
      expect(ctx.isReady, isTrue);
      expect(ctx.paymentsAvailable, isTrue);
      expect(notifications, 0);
    });

    test('a failed apply leaves them closed (fail closed)', () async {
      final ctx = StripeAccountContext()
        ..applyToStripe = (_) async => throw StateError('stripe down');

      await ctx.apply('acct_a');

      expect(ctx.isReady, isTrue); // resolved…
      expect(ctx.paymentsAvailable, isFalse); // …but refused
    });
  });

  group('SelectedGym.setActiveGym drives the connected-account context', () {
    // The suite-wide flutter_test_config no-ops the global applier; swap in a
    // recorder for these to observe what setActiveGym pushes.
    late List<String?> applied;

    setUp(() {
      applied = <String?>[];
      stripeAccountContext.applyToStripe = (id) async => applied.add(id);
    });

    tearDown(() {
      selectedGym.reset();
      stripeAccountContext.applyToStripe = (id) async {};
    });

    test('activating a gym with an acct_ applies it', () async {
      selectedGym.setActiveGym(
        gymId: 'gym-1',
        displayName: 'Iron Den',
        role: EmployeeRole.owner,
        timezone: 'America/Chicago',
        logoUrl: null,
        stripeAccountId: 'acct_iron',
      );
      // setActiveGym does not await the apply; let the microtask drain.
      await Future<void>.delayed(Duration.zero);

      expect(applied, ['acct_iron']);
      expect(selectedGym.stripeAccountId, 'acct_iron');
    });

    test('leaves the gates CLOSED for the whole in-flight apply', () async {
      final gate = Completer<void>();
      stripeAccountContext.applyToStripe = (id) {
        applied.add(id);
        return gate.future;
      };

      selectedGym.setActiveGym(
        gymId: 'gym-switch',
        displayName: 'Switched To',
        role: EmployeeRole.owner,
        timezone: 'America/Chicago',
        logoUrl: null,
        stripeAccountId: 'acct_switch_target',
      );

      // setActiveGym is synchronous and notifies its own listeners right here,
      // so this is the state every gym-switch consumer sees. Neither flag may
      // still be reporting the gym we just switched AWAY from.
      expect(stripeAccountContext.isReady, isFalse);
      expect(stripeAccountContext.paymentsAvailable, isFalse);

      gate.complete();
      await Future<void>.delayed(Duration.zero);

      expect(applied, ['acct_switch_target']);
      expect(stripeAccountContext.isReady, isTrue);
      expect(stripeAccountContext.paymentsAvailable, isTrue);
    });

    test('activating a not-onboarded gym applies null (payments unavailable)',
        () async {
      selectedGym.setActiveGym(
        gymId: 'gym-2',
        displayName: 'No Stripe Yet',
        role: EmployeeRole.owner,
        timezone: 'America/Chicago',
        logoUrl: null,
        stripeAccountId: null,
      );
      await Future<void>.delayed(Duration.zero);

      expect(applied, [null]);
      expect(selectedGym.stripeAccountId, isNull);
    });
  });
}
