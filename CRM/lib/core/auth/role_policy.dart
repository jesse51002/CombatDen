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
  // WRITE gate for the gym catalog (create / edit / delete / promote / toggle
  // / reorder). Reading the catalog is the separate [canViewCatalog] (staff).
  bool get canConfigureCatalog => _isStaffAdmin;
  bool get canManageMemberApp => _isStaffAdmin;
  bool get canManageGymSettings => _isStaffAdmin;
  bool get canViewGrowth => _isStaffAdmin;
  bool get canAdjustPoints => _isStaffAdmin;
  bool get canPromoteRank => _isStaffAdmin;
  bool get canEditSchedule => _isStaffAdmin;
  bool get canBulkReprice => _isStaffAdmin;
  bool get canRemovePayerLink => _isStaffAdmin;
  // Download the gym's records as zipped CSVs (the Settings → Reports & exports
  // section, backed by the owner/admin-only backend report + full-export
  // routes). Its own capability, not [canManageGymSettings]: front desk reaches
  // the Settings screen for appearance / QR but must never see this section.
  bool get canExportReports => _isStaffAdmin;
  // The Dashboard's overview / financial cards (the Total Members hero now, a
  // gym-income module later) — owner/admin only, even though front desk can
  // reach the Dashboard itself for its operational cards ([canViewDashboard]).
  bool get canViewGymAnalytics => _isStaffAdmin;

  // ── Staff capabilities (owner / admin / front desk) ──
  bool get canViewMembers => _isStaff;
  bool get canCreateMembers => _isStaff;
  bool get canEditMemberProfile => _isStaff;
  bool get canManageMemberBilling => _isStaff;
  bool get canMutateMemberships => _isStaff;
  /// Reprice a SINGLE membership to its plan's current ACTIVE price — a
  /// correction of an outdated-price membership, NOT setting a custom amount
  /// (despite the legacy name). This is a member-money operation front desk
  /// performs, so it is staff-wide. Plan-wide reprice stays owner/admin
  /// ([canBulkReprice]).
  bool get canSetCustomMembershipPrice => _isStaff;
  bool get canRedeemRewards => _isStaff;
  bool get canApproveRedemptions => _isStaff;
  bool get canCheckInMembers => _isStaff;
  bool get canSignWaivers => _isStaff;
  bool get canCreatePayerLink => _isStaff;
  bool get canEditSingleOccurrence => _isStaff;
  bool get canOperateKiosk => _isStaff;
  bool get canUseAppearanceSettings => _isStaff;
  // Front desk reaches the Dashboard for its OPERATIONAL cards (live
  // attendance, overdue payments, upcoming classes); the overview/financial
  // cards on it are separately gated by [canViewGymAnalytics] (owner/admin).
  bool get canViewDashboard => _isStaff;
  // READ-only access to the gym catalog (the /memberships view tabs). WRITING
  // it is the separate [canConfigureCatalog] (owner/admin) gate.
  bool get canViewCatalog => _isStaff;

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
  /// swallow `/memberships` (a distinct catalog section — staff can VIEW it,
  /// only owner/admin can reach its editors).
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
    // Catalog editors/detail = WRITE surfaces (owner/admin). Tested BEFORE the
    // broad /memberships view prefix so a deep-link can't reach an editor.
    // The rank DETAIL view (/memberships/ranks/detail) is deliberately absent
    // here — it is a read surface, so it falls through to [canViewCatalog].
    if (path.startsWith(AppRoutes.membershipDetails) ||
        path.startsWith(AppRoutes.membershipsWaiverEditor) ||
        path.startsWith(AppRoutes.membershipsRankEditor) ||
        path.startsWith(AppRoutes.membershipsRankPresets)) {
      return canConfigureCatalog;
    }
    if (path.startsWith(AppRoutes.memberships)) return canViewCatalog;
    if (path.startsWith(AppRoutes.schedule)) return canViewSchedule;
    if (path == AppRoutes.settings) {
      return canUseAppearanceSettings ||
          canOperateKiosk ||
          canManageGymSettings;
    }
    return true; // login / gym-setup / anything else — don't gate.
  }
}
