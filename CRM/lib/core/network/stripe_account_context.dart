import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

/// Applies a gym's Stripe **Connect connected account** to the Stripe.js client
/// so a browser-tokenized card is minted on that connected account.
///
/// **Why this exists (the correctness crux).** The backend runs direct-charge
/// Connect: every customer, PaymentMethod, and subscription lives on the gym's
/// connected account, and Stripe forbids attaching a PLATFORM-owned `pm_…` to a
/// connected-account customer. `main.dart` sets only the platform publishable
/// key, so without this the card the browser tokenizes is platform-owned and
/// its attach 500s (the kiosk signup hit this 100% of the time).
///
/// **The ordering hazard.** A Stripe `CardField` binds to whichever JS Stripe
/// object exists AT MOUNT TIME. `applySettings()` re-creates that JS object with
/// the connected account, so it must be **awaited before any card field mounts**,
/// and re-applied on every gym switch (switching after a field is mounted throws
/// "the Element belongs to a different instance of Stripe"). The shared
/// `CardFieldBox` gates its field on [isReady] / [paymentsAvailable], so the
/// await-before-mount ordering is guaranteed rather than hoped for.
///
/// **Both gates CLOSE for the duration of an apply**, which is what makes that
/// guarantee real. Nobody awaits [apply] — [SelectedGym.setActiveGym] is
/// synchronous and fires it — so if the flags kept the previous gym's `true`
/// while the new account was still being applied, a card field mounting in that
/// window would bind to the OUTGOING gym's JS Stripe object and tokenize the
/// card on the wrong connected account. [apply] therefore drops [isReady] and
/// [paymentsAvailable] to false synchronously, before its first await.
///
/// **Fail closed.** A null/empty account — a gym that has not finished Stripe
/// onboarding — leaves payments UNAVAILABLE: no card field is mounted, so the
/// client can never tokenize onto the platform account. An `applySettings()`
/// failure is treated the same way.
class StripeAccountContext extends ChangeNotifier {
  /// The Stripe side effect, injectable so the seam is unit-testable without a
  /// live Stripe.js (and so the whole test suite can no-op it — see
  /// `test/flutter_test_config.dart`). Production sets the connected account on
  /// Stripe.js and re-initializes the JS Stripe object.
  Future<void> Function(String? accountId) applyToStripe = _applyToStripe;

  static Future<void> _applyToStripe(String? accountId) async {
    // Setting null clears the context back to the platform account; a non-null
    // `acct_…` scopes tokenization to that connected account.
    Stripe.stripeAccountId = accountId;
    // Recreates the underlying JS Stripe object with the new account, which is
    // what a not-yet-mounted CardField will bind to.
    await Stripe.instance.applySettings();
  }

  String? _appliedAccountId;
  bool _hasResolved = false;
  bool _paymentsAvailable = false;
  Object? _error;

  /// The connected account currently applied (null = none / cleared).
  String? get appliedAccountId => _appliedAccountId;

  /// Whether the context has resolved for the account currently being applied —
  /// the readiness the shared card field waits on before mounting. Goes back to
  /// false for the duration of every [apply] (including a gym switch), so it is
  /// never `true` while the applied account is the previous gym's.
  bool get isReady => _hasResolved;

  /// Whether a connected account is applied and card entry may proceed. False
  /// for a null account (gym not onboarded), a failed apply, and for the
  /// duration of an in-flight [apply] — **fail closed**.
  bool get paymentsAvailable => _paymentsAvailable;

  /// The last apply error, or null. Kept so a retry with the same account is
  /// not short-circuited as an unchanged no-op.
  Object? get error => _error;

  /// Apply [accountId] (an `acct_…`, or null when the gym has no connected
  /// account) to the Stripe.js client.
  ///
  /// Idempotent: re-applying the SAME account after a success is a no-op, so a
  /// mounted card field is never needlessly rebound to a fresh JS Stripe object.
  /// A DIFFERENT account (a gym switch) re-applies. **Never throws** — a Stripe
  /// failure fails closed (payments unavailable), so a card field is refused
  /// rather than mounted against the wrong (platform) account.
  ///
  /// **Closes both gates first.** Until `applyToStripe` returns, Stripe.js still
  /// carries the PREVIOUS account, so [isReady] / [paymentsAvailable] drop to
  /// false synchronously (before the first await) and listeners are notified —
  /// no consumer can read a stale `true` and mount a card field against the
  /// outgoing gym's connected account. See the class doc's ordering hazard.
  Future<void> apply(String? accountId) async {
    final normalized =
        (accountId != null && accountId.isNotEmpty) ? accountId : null;

    // Nothing changed and the last apply succeeded: skip. Re-creating the JS
    // Stripe object under a live CardField would throw the "different instance"
    // error, so an unchanged account must not re-apply. This check stays ABOVE
    // the gate close below for the same reason: closing the gates tears a
    // mounted field down, so a redundant re-apply must not even flicker it.
    if (_hasResolved && _error == null && normalized == _appliedAccountId) {
      return;
    }

    // Close the gates for the DURATION of the apply. A field already mounted
    // against the previous account is torn down to CardFieldBox's "Preparing
    // secure card entry…" box and remounts once the new account is live, which
    // also sidesteps Stripe's "Element belongs to a different instance of
    // Stripe" throw.
    _hasResolved = false;
    _paymentsAvailable = false;
    notifyListeners();

    try {
      await applyToStripe(normalized);
      _appliedAccountId = normalized;
      _paymentsAvailable = normalized != null;
      _error = null;
    } catch (e, s) {
      log('Stripe connected-account apply failed',
          error: e, stackTrace: s);
      _error = e;
      _appliedAccountId = null;
      // Fail closed: never let a card field mount and tokenize on the platform.
      _paymentsAvailable = false;
    } finally {
      _hasResolved = true;
      notifyListeners();
    }
  }
}

/// The one process-wide Stripe connected-account context. Driven by the gym
/// state ([SelectedGym.setActiveGym] applies the active gym's account); read by
/// the shared `CardFieldBox` to gate card-field mounting.
final StripeAccountContext stripeAccountContext = StripeAccountContext();
