import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/navigation/app_routes.dart';

/// The single capability source for the CRM — what each [EmployeeRole] may do.
///
/// Two tiers underlie every capability:
/// - **staff admin** = owner or admin: full configuration + management access.
/// - **staff** = staff admin OR front desk: day-to-day member operations.
///
/// [EmployeeRole.unknown] falls through both tiers, so it behaves as the
/// trainer tier (least privilege) — a forward-compat role we don't recognize
/// gets the safest, most limited access.
///
/// Every gate in nav, routing, and section visibility reads these getters;
/// nothing hard-codes a role comparison. Read-only affordance gating (e.g. a
/// trainer viewing but not editing the schedule) is enforced at the widget
/// layer, not here — [canViewSchedule] is `true` for everyone.
extension RolePolicy on EmployeeRole {
  bool get _isStaffAdmin =>
      this == EmployeeRole.owner || this == EmployeeRole.admin;
  bool get _isStaff => _isStaffAdmin || this == EmployeeRole.frontDesk;

  // ── Staff-admin capabilities (owner / admin only) ──
  bool get canManageStaff => _isStaffAdmin;
  bool get canConfigureCatalog => _isStaffAdmin;
  bool get canManageMemberApp => _isStaffAdmin;
  bool get canManageGymSettings => _isStaffAdmin;
  bool get canViewDashboard => _isStaffAdmin;
  bool get canViewGrowth => _isStaffAdmin;
  bool get canAdjustPoints => _isStaffAdmin;
  bool get canPromoteRank => _isStaffAdmin;
  bool get canEditSchedule => _isStaffAdmin;
  bool get canSetCustomMembershipPrice => _isStaffAdmin;
  bool get canBulkReprice => _isStaffAdmin;
  bool get canRemovePayerLink => _isStaffAdmin;

  // ── Staff capabilities (owner / admin / front desk) ──
  bool get canViewMembers => _isStaff;
  bool get canCreateMembers => _isStaff;
  bool get canEditMemberProfile => _isStaff;
  bool get canManageMemberBilling => _isStaff;
  bool get canMutateMemberships => _isStaff;
  bool get canRedeemRewards => _isStaff;
  bool get canApproveRedemptions => _isStaff;
  bool get canCheckInMembers => _isStaff;
  bool get canSignWaivers => _isStaff;
  bool get canCreatePayerLink => _isStaff;
  bool get canEditSingleOccurrence => _isStaff;
  bool get canOperateKiosk => _isStaff;
  bool get canUseAppearanceSettings => _isStaff;

  // ── Everyone (trainer is read-only, gated at the affordance layer) ──
  bool get canViewSchedule => true;

  // ── Owner only ──
  bool get canDeleteGym => this == EmployeeRole.owner;

  /// Where this role lands after gym activation, and where a denied route
  /// redirects to. Staff admins land on the dashboard; front desk on the
  /// members list; trainer / unknown on the (read-only) schedule.
  String get landingRoute {
    if (_isStaffAdmin) return AppRoutes.home;
    if (this == EmployeeRole.frontDesk) return AppRoutes.members;
    return AppRoutes.schedule; // trainer / unknown
  }

  /// Whether this role may open [path]. Non-app routes (login, gym setup, or
  /// anything unrecognized) are never gated — they pass through as `true`.
  ///
  /// Order matters: more specific prefixes must be tested before the broader
  /// ones they sit under. The member-app preview lives under `/members`, so it
  /// is checked first; and the `/members` test is slash-bounded so it cannot
  /// swallow `/memberships` (which is a distinct, staff-admin-only section).
  bool canAccessRoute(String path) {
    if (path.startsWith(AppRoutes.memberAppPreview)) {
      return canManageMemberApp;
    }
    // Slash-bounded so `/memberships*` is NOT matched here (`/memberships`
    // starts with `/members` as a raw prefix). `/members` and its member
    // detail sub-paths resolve to the members-view capability.
    if (path == AppRoutes.members ||
        path.startsWith('${AppRoutes.members}/')) {
      return canViewMembers;
    }
    if (path == AppRoutes.home) return canViewDashboard;
    if (path.startsWith(AppRoutes.employees)) return canManageStaff;
    if (path.startsWith(AppRoutes.growth)) return canViewGrowth;
    if (path.startsWith(AppRoutes.memberships)) return canConfigureCatalog;
    if (path.startsWith(AppRoutes.schedule)) return canViewSchedule;
    if (path == AppRoutes.settings) {
      return canUseAppearanceSettings ||
          canOperateKiosk ||
          canManageGymSettings;
    }
    return true; // login / gym-setup / anything else — don't gate.
  }
}
