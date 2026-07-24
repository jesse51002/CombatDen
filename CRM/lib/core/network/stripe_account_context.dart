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

  /// Whether the context has resolved at least once for the current account —
  /// the readiness the shared card field waits on before mounting.
  bool get isReady => _hasResolved;

  /// Whether a connected account is applied and card entry may proceed. False
  /// for a null account (gym not onboarded) or a failed apply — **fail closed**.
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
  Future<void> apply(String? accountId) async {
    final normalized =
        (accountId != null && accountId.isNotEmpty) ? accountId : null;

    // Nothing changed and the last apply succeeded: skip. Re-creating the JS
    // Stripe object under a live CardField would throw the "different instance"
    // error, so an unchanged account must not re-apply.
    if (_hasResolved && _error == null && normalized == _appliedAccountId) {
      return;
    }

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
