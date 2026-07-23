/// Named routes for the AppManagement web prototype.
///
/// Mirrors `MobileApp/lib/core/navigation/app_routes.dart`'s pattern:
/// a single class of string constants, used by `MaterialApp.routes` in
/// `main.dart` and by every screen's navigation calls.
class AppRoutes {
  static const String home = '/';
  static const String members = '/members';
  static const String memberDetail = '/members/detail';
  static const String memberAppPreview = '/members/app-preview';
  // Deep-linkable tabs within the Member App screen. The base
  // [memberAppPreview] path means the Theme tab.
  static const String memberAppPreviewVideos = '/members/app-preview/videos';
  static const String memberAppPreviewLoyalty = '/members/app-preview/loyalty';
  static const String schedule = '/schedule';
  static const String scheduleAddClass = '/schedule/class/new';
  static const String scheduleEditClass = '/schedule/class/edit';
  // The single-occurrence edit screen, opened from the chooser dialog's
  // "This occurrence" option.
  static const String scheduleOccurrence = '/schedule/class/occurrence';
  // The Gym screen's four tabs are each addressable. (The route path
  // stays /memberships — the nav section is labelled "Gym".)
  static const String memberships = '/memberships';
  static const String membershipsDiscounts = '/memberships/discounts';
  static const String membershipsWaivers = '/memberships/waivers';
  static const String membershipsRanks = '/memberships/ranks';
  // A single main rank's detail view (members-in-rank + promote).
  // Deep-linkable by rank id, same round-trip shape as
  // [memberDetailPath] / [memberIdFromPath].
  static const String membershipsRankDetail = '/memberships/ranks/detail';
  // The preset picker screen (pushed with BlocProvider.value, keeps
  // the parent Ranks tab's URL — not independently addressable).
  static const String membershipsRankPresets = '/memberships/ranks/presets';
  // Create / edit a main rank (full-screen form). Reads the rank (or
  // null for create) off route arguments, so it is not deep-linkable.
  static const String membershipsRankEditor = '/memberships/ranks/editor';
  // Create / edit a membership plan. Reads the plan (or null for
  // create) off route arguments, so it is not deep-linkable.
  static const String membershipDetails = '/memberships/detail';
  // Create / edit a waiver (rich-text editor + versions + signed-members
  // tab). Reads the waiver (or null for create) off route arguments, so it
  // is not deep-linkable.
  static const String membershipsWaiverEditor =
      '/memberships/waivers/editor';
  // The Growth screen's six tabs are each addressable. The base
  // [growth] path is the Overview tab; the ordered list backing the
  // deep-link ↔ tab-index mapping is `kGrowthTabRoutes` in
  // `growth_screen.dart`.
  static const String growth = '/growth';
  static const String growthMembers = '/growth/members';
  static const String growthRevenue = '/growth/revenue';
  static const String growthAttendance = '/growth/attendance';
  static const String growthTrial = '/growth/trial';
  static const String growthRetention = '/growth/retention';
  static const String employees = '/employees';
  static const String employeeDetail = '/employees/detail';
  // Settings hosts the appearance (theme) control, the gym timezone
  // setting, and the printable sign-up / check-in QR codes.
  static const String settings = '/settings';

  // Video-agent screen: reachable from the member-app preview's Videos
  // tab (the Edit & Focus card). A sub-route of that section — not in
  // kAddressableRoutes, so it keeps its parent section's URL.
  static const String videoAgent = '/members/app-preview/video-agent';

  /// Deep-link path for a specific member's detail page —
  /// `/members/detail/<memberId>`. Opening a member writes this to the
  /// URL so a reload restores that member; the id is parsed back out by
  /// [memberIdFromPath] in `_onGenerateRoute`.
  static String memberDetailPath(String memberId) =>
      '$memberDetail/$memberId';

  /// The member id from a `/members/detail/<id>` path, or null when
  /// [path] is not a specific-member deep link (the bare [memberDetail]
  /// route, or any other route). Round-trips with [memberDetailPath].
  static String? memberIdFromPath(String path) {
    const prefix = '$memberDetail/';
    if (!path.startsWith(prefix)) return null;
    final id = path.substring(prefix.length);
    return id.isEmpty ? null : id;
  }

  /// Deep-link path for a specific main rank's detail page —
  /// `/memberships/ranks/detail/<mainRankId>`. Round-trips with
  /// [mainRankIdFromPath] (mirrors [memberDetailPath]).
  static String membershipsRankDetailPath(String mainRankId) =>
      '$membershipsRankDetail/$mainRankId';

  /// The main rank id from a `/memberships/ranks/detail/<id>` path,
  /// or null when [path] is not a specific-rank deep link. Round-trips
  /// with [membershipsRankDetailPath] (mirrors [memberIdFromPath]).
  static String? mainRankIdFromPath(String path) {
    const prefix = '$membershipsRankDetail/';
    if (!path.startsWith(prefix)) return null;
    final id = path.substring(prefix.length);
    return id.isEmpty ? null : id;
  }

  /// Deep-link path for a specific employee's detail page —
  /// `/employees/detail/<employeeId>`. Round-trips with
  /// [employeeIdFromPath] (mirrors [memberDetailPath]).
  static String employeeDetailPath(String employeeId) =>
      '$employeeDetail/$employeeId';

  /// The employee id from an `/employees/detail/<id>` path, or null when
  /// [path] is not a specific-employee deep link (the bare [employeeDetail]
  /// route, or any other route). Round-trips with [employeeDetailPath].
  static String? employeeIdFromPath(String path) {
    const prefix = '$employeeDetail/';
    if (!path.startsWith(prefix)) return null;
    final id = path.substring(prefix.length);
    return id.isEmpty ? null : id;
  }

  AppRoutes._();
}
