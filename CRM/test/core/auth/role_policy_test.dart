import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/navigation/app_routes.dart';

/// Staff-admin capabilities: true for owner/admin only.
const Map<String, bool Function(EmployeeRole)> _staffAdminCapabilities = {
  'canManageStaff': _canManageStaff,
  'canConfigureCatalog': _canConfigureCatalog,
  'canManageMemberApp': _canManageMemberApp,
  'canManageGymSettings': _canManageGymSettings,
  'canViewGymAnalytics': _canViewGymAnalytics,
  'canViewGrowth': _canViewGrowth,
  'canAdjustPoints': _canAdjustPoints,
  'canPromoteRank': _canPromoteRank,
  'canEditSchedule': _canEditSchedule,
  'canBulkReprice': _canBulkReprice,
  'canRemovePayerLink': _canRemovePayerLink,
  'canExportReports': _canExportReports,
};

bool _canManageStaff(EmployeeRole r) => r.canManageStaff;
bool _canConfigureCatalog(EmployeeRole r) => r.canConfigureCatalog;
bool _canManageMemberApp(EmployeeRole r) => r.canManageMemberApp;
bool _canManageGymSettings(EmployeeRole r) => r.canManageGymSettings;
bool _canViewGymAnalytics(EmployeeRole r) => r.canViewGymAnalytics;
bool _canViewGrowth(EmployeeRole r) => r.canViewGrowth;
bool _canAdjustPoints(EmployeeRole r) => r.canAdjustPoints;
bool _canPromoteRank(EmployeeRole r) => r.canPromoteRank;
bool _canEditSchedule(EmployeeRole r) => r.canEditSchedule;
bool _canBulkReprice(EmployeeRole r) => r.canBulkReprice;
bool _canRemovePayerLink(EmployeeRole r) => r.canRemovePayerLink;
bool _canExportReports(EmployeeRole r) => r.canExportReports;

/// Staff capabilities: true for owner/admin/front_desk.
const Map<String, bool Function(EmployeeRole)> _staffCapabilities = {
  'canViewMembers': _canViewMembers,
  'canCreateMembers': _canCreateMembers,
  'canEditMemberProfile': _canEditMemberProfile,
  'canManageMemberBilling': _canManageMemberBilling,
  'canMutateMemberships': _canMutateMemberships,
  // Single-membership reprice to the plan's ACTIVE price is a member-money
  // correction front desk performs, so it is staff-wide (owner/admin/front
  // desk) — NOT staff-admin. Plan-wide reprice (canBulkReprice) stays
  // staff-admin. See role_policy.dart and the employees-guide capability
  // matrix.
  'canSetCustomMembershipPrice': _canSetCustomMembershipPrice,
  'canRedeemRewards': _canRedeemRewards,
  'canApproveRedemptions': _canApproveRedemptions,
  'canCheckInMembers': _canCheckInMembers,
  'canSignWaivers': _canSignWaivers,
  'canCreatePayerLink': _canCreatePayerLink,
  'canEditSingleOccurrence': _canEditSingleOccurrence,
  'canOperateKiosk': _canOperateKiosk,
  'canUseAppearanceSettings': _canUseAppearanceSettings,
  'canViewDashboard': _canViewDashboard,
  'canViewCatalog': _canViewCatalog,
};

bool _canViewDashboard(EmployeeRole r) => r.canViewDashboard;
bool _canViewCatalog(EmployeeRole r) => r.canViewCatalog;
bool _canViewMembers(EmployeeRole r) => r.canViewMembers;
bool _canCreateMembers(EmployeeRole r) => r.canCreateMembers;
bool _canEditMemberProfile(EmployeeRole r) => r.canEditMemberProfile;
bool _canManageMemberBilling(EmployeeRole r) => r.canManageMemberBilling;
bool _canMutateMemberships(EmployeeRole r) => r.canMutateMemberships;
bool _canSetCustomMembershipPrice(EmployeeRole r) =>
    r.canSetCustomMembershipPrice;
bool _canRedeemRewards(EmployeeRole r) => r.canRedeemRewards;
bool _canApproveRedemptions(EmployeeRole r) => r.canApproveRedemptions;
bool _canCheckInMembers(EmployeeRole r) => r.canCheckInMembers;
bool _canSignWaivers(EmployeeRole r) => r.canSignWaivers;
bool _canCreatePayerLink(EmployeeRole r) => r.canCreatePayerLink;
bool _canEditSingleOccurrence(EmployeeRole r) => r.canEditSingleOccurrence;
bool _canOperateKiosk(EmployeeRole r) => r.canOperateKiosk;
bool _canUseAppearanceSettings(EmployeeRole r) => r.canUseAppearanceSettings;

const Set<EmployeeRole> _staffAdminRoles = {
  EmployeeRole.owner,
  EmployeeRole.admin,
};
const Set<EmployeeRole> _staffRoles = {
  EmployeeRole.owner,
  EmployeeRole.admin,
  EmployeeRole.frontDesk,
};

void main() {
  group('RolePolicy capability matrix (table-driven over every role)', () {
    for (final role in EmployeeRole.values) {
      group(role.name, () {
        for (final entry in _staffAdminCapabilities.entries) {
          test('${entry.key} (staff-admin set)', () {
            expect(entry.value(role), _staffAdminRoles.contains(role));
          });
        }

        for (final entry in _staffCapabilities.entries) {
          test('${entry.key} (staff set)', () {
            expect(entry.value(role), _staffRoles.contains(role));
          });
        }

        test('canViewSchedule is always true (read-only for everyone)', () {
          expect(role.canViewSchedule, isTrue);
        });

        test('canDeleteGym is owner-only', () {
          expect(role.canDeleteGym, role == EmployeeRole.owner);
        });
      });
    }
  });

  group('RolePolicy.landingRoute', () {
    test('owner and admin land on the dashboard', () {
      expect(EmployeeRole.owner.landingRoute, AppRoutes.home);
      expect(EmployeeRole.admin.landingRoute, AppRoutes.home);
    });

    test('front desk lands on the members list', () {
      expect(EmployeeRole.frontDesk.landingRoute, AppRoutes.members);
    });

    test('trainer and unknown land on the (read-only) schedule', () {
      expect(EmployeeRole.trainer.landingRoute, AppRoutes.schedule);
      expect(EmployeeRole.unknown.landingRoute, AppRoutes.schedule);
    });
  });

  group('RolePolicy.canAccessRoute', () {
    // The catalog view tabs (front desk MAY open) vs the editor/detail-form
    // routes (owner/admin only). The rank DETAIL view is a VIEW route.
    const catalogViewRoutes = [
      AppRoutes.memberships,
      AppRoutes.membershipsDiscounts,
      AppRoutes.membershipsWaivers,
      AppRoutes.membershipsRanks,
      AppRoutes.membershipsRankDetail,
    ];
    const catalogEditorRoutes = [
      AppRoutes.membershipDetails,
      AppRoutes.membershipsWaiverEditor,
      AppRoutes.membershipsRankEditor,
      AppRoutes.membershipsRankPresets,
    ];

    test(
      'front desk gets a READ-ONLY catalog: every /memberships view tab '
      '(including the rank DETAIL view) is accessible; every editor / '
      'detail-form route is NOT',
      () {
        for (final route in catalogViewRoutes) {
          expect(
            EmployeeRole.frontDesk.canAccessRoute(route),
            isTrue,
            reason: 'view route=$route',
          );
        }
        for (final route in catalogEditorRoutes) {
          expect(
            EmployeeRole.frontDesk.canAccessRoute(route),
            isFalse,
            reason: 'editor route=$route',
          );
        }
      },
    );

    test(
      'catalog VIEW routes are staff (owner/admin/front desk); EDITOR routes '
      'are staff-admin (owner/admin) only',
      () {
        for (final route in catalogViewRoutes) {
          for (final role in EmployeeRole.values) {
            expect(
              role.canAccessRoute(route),
              _staffRoles.contains(role),
              reason: 'view route=$route role=${role.name}',
            );
          }
        }
        for (final route in catalogEditorRoutes) {
          for (final role in EmployeeRole.values) {
            expect(
              role.canAccessRoute(route),
              _staffAdminRoles.contains(role),
              reason: 'editor route=$route role=${role.name}',
            );
          }
        }
      },
    );

    test(
      'regression guard: the /members slash-bounded prefix must not swallow '
      '/memberships (a distinct catalog section) — trainer may view neither',
      () {
        expect(
          EmployeeRole.trainer.canAccessRoute(AppRoutes.memberships),
          isFalse,
        );
      },
    );

    test(
      '/members and a member-detail deep link ARE accessible to front desk',
      () {
        expect(
          EmployeeRole.frontDesk.canAccessRoute(AppRoutes.members),
          isTrue,
        );
        expect(
          EmployeeRole.frontDesk
              .canAccessRoute(AppRoutes.memberDetailPath('member-1')),
          isTrue,
        );
      },
    );

    test(
      '/members/app-preview is owner/admin only, NOT front desk (checked '
      'before the /members prefix so it is not swallowed by it either)',
      () {
        expect(
          EmployeeRole.frontDesk.canAccessRoute(AppRoutes.memberAppPreview),
          isFalse,
        );
        expect(
          EmployeeRole.owner.canAccessRoute(AppRoutes.memberAppPreview),
          isTrue,
        );
        expect(
          EmployeeRole.admin.canAccessRoute(AppRoutes.memberAppPreview),
          isTrue,
        );
      },
    );

    test('/schedule is accessible to every role, including trainer', () {
      for (final role in EmployeeRole.values) {
        expect(
          role.canAccessRoute(AppRoutes.schedule),
          isTrue,
          reason: 'role=${role.name}',
        );
      }
    });

    test('/settings is accessible to front desk but NOT trainer', () {
      expect(EmployeeRole.frontDesk.canAccessRoute(AppRoutes.settings), isTrue);
      expect(EmployeeRole.trainer.canAccessRoute(AppRoutes.settings), isFalse);
    });

    test('/growth is owner/admin only', () {
      for (final role in EmployeeRole.values) {
        expect(
          role.canAccessRoute(AppRoutes.growth),
          _staffAdminRoles.contains(role),
          reason: 'role=${role.name}',
        );
      }
    });

    test(
      '/ (dashboard) is now staff — owner/admin AND front desk reach it; '
      'trainer/unknown are denied',
      () {
        for (final role in EmployeeRole.values) {
          expect(
            role.canAccessRoute(AppRoutes.home),
            _staffRoles.contains(role),
            reason: 'role=${role.name}',
          );
        }
      },
    );
  });
}
