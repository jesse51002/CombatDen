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
  // The Memberships screen's three tabs are each addressable.
  static const String memberships = '/memberships';
  static const String membershipsDiscounts = '/memberships/discounts';
  static const String membershipsWaivers = '/memberships/waivers';
  // Create / edit a membership plan. Reads the plan (or null for
  // create) off route arguments, so it is not deep-linkable.
  static const String membershipDetails = '/memberships/detail';
  // Create / edit a waiver (rich-text editor + versions + signed-members
  // tab). Reads the waiver (or null for create) off route arguments, so it
  // is not deep-linkable.
  static const String membershipsWaiverEditor =
      '/memberships/waivers/editor';
  static const String growth = '/growth';
  static const String employees = '/employees';
  static const String employeeDetail = '/employees/detail';
  // Settings hosts the appearance (theme) control and the printable
  // sign-up / check-in QR codes.
  static const String settings = '/settings';

  // Video-config agent screen: reachable from the Settings page.
  static const String videoConfig = '/settings/video-config';

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

  AppRoutes._();
}
