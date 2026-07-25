import 'dart:async';

import 'package:crm/core/network/stripe_account_context.dart';

/// Runs once before the whole CRM test suite (Flutter's `flutter_test_config`
/// convention). Replaces the Stripe connected-account applier with an in-memory
/// no-op so a `selectedGym.setActiveGym(...)` in any test never reaches the real
/// Stripe.js platform channel (unavailable / hanging under `flutter test`). The
/// seam's own apply/switch/null-fail-closed logic is unit-tested directly with
/// an injected recorder in `test/core/network/stripe_account_context_test.dart`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  stripeAccountContext.applyToStripe = (accountId) async {};
  await testMain();
}
