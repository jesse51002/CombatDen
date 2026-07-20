import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/home/data/mock_member_stats.dart';
import 'package:crm/features/home/presentation/widgets/total_members_hero/total_members_hero.dart';

/// The Dashboard's Total Members hero is an overview/analytics card gated by
/// [RolePolicy.canViewGymAnalytics] — owner/admin only. Front desk reaches the
/// Dashboard for its OPERATIONAL cards but does NOT see the hero.
///
/// This pumps the real [TotalMembersHero] behind the exact gate expression
/// `HomeScreen` uses (`selectedGym.role?.canViewGymAnalytics ?? false`). The
/// full `HomeScreen` can't be unit-pumped: its operational cards self-provide
/// network-backed blocs (the Live Attendance card runs a 60s poll `Timer`),
/// so a pump leaves pending timers with no injection seam. The gate getter
/// itself is separately locked down in `test/core/auth/role_policy_test.dart`.
void main() {
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

  // Mirrors HomeScreen's hero gate over the real hero widget.
  Widget harness() {
    return MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: selectedGym,
          builder: (context, _) {
            final showHero = selectedGym.role?.canViewGymAnalytics ?? false;
            return Column(
              children: [
                if (showHero) TotalMembersHero(stats: kMockMemberStats),
              ],
            );
          },
        ),
      ),
    );
  }

  testWidgets('front desk does NOT see the Total Members hero', (tester) async {
    activate(EmployeeRole.frontDesk);
    await tester.pumpWidget(harness());

    expect(find.byType(TotalMembersHero), findsNothing);
  });

  testWidgets('owner DOES see the Total Members hero', (tester) async {
    activate(EmployeeRole.owner);
    await tester.pumpWidget(harness());

    expect(find.byType(TotalMembersHero), findsOneWidget);
  });
}
