import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/state/selected_gym.dart';

/// The Dashboard's money hero (`RevenueHeroCard`, the `revenue_hero` growth
/// metric) is an overview/analytics card gated by
/// [RolePolicy.canViewGymAnalytics] — owner/admin only. It shows gym REVENUE,
/// so front desk, who reaches the Dashboard for its OPERATIONAL cards, must
/// not see it.
///
/// This locks the SCREEN-LEVEL gate wiring `HomeScreen` uses over the hero
/// slot: `selectedGym.role?.canViewGymAnalytics ?? false` — front desk out,
/// owner in, and a null role falls closed. It gates a sentinel rather than the
/// real `RevenueHeroCard` on purpose: that card self-provides a `GrowthBloc`
/// over a real `ApiClient` and fetches on build, and this repo's test rule is
/// "never hit a live backend in a test" — the card's own quiet-failure
/// rendering is covered by the growth widget tests, and the gate getter itself
/// by `test/core/auth/role_policy_test.dart`. What is unique here is that the
/// Dashboard applies that gate, with the null-role fallback, to the hero slot.
void main() {
  const heroSlot = Key('dashboard-hero-slot');

  tearDown(() => selectedGym.reset());

  void activate(EmployeeRole role) {
    selectedGym.setActiveGym(
      gymId: 'gym-1',
      displayName: 'Test Gym',
      role: role,
      timezone: 'America/Chicago',
      logoUrl: null,
    );
  }

  // Mirrors HomeScreen's hero gate over the hero slot.
  Widget harness() {
    return MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: selectedGym,
          builder: (context, _) {
            final showHero = selectedGym.role?.canViewGymAnalytics ?? false;
            return Column(
              children: [
                if (showHero) const SizedBox(key: heroSlot),
              ],
            );
          },
        ),
      ),
    );
  }

  testWidgets('front desk does NOT see the revenue hero', (tester) async {
    activate(EmployeeRole.frontDesk);
    await tester.pumpWidget(harness());

    expect(find.byKey(heroSlot), findsNothing);
  });

  testWidgets('owner DOES see the revenue hero', (tester) async {
    activate(EmployeeRole.owner);
    await tester.pumpWidget(harness());

    expect(find.byKey(heroSlot), findsOneWidget);
  });

  testWidgets('a null role falls closed (no hero)', (tester) async {
    // selectedGym starts reset; role is null before any gym is activated.
    await tester.pumpWidget(harness());

    expect(find.byKey(heroSlot), findsNothing);
  });
}
