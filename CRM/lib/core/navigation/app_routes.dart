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
  static const String qrCodes = '/qr-codes';
  static const String growth = '/growth';
  static const String employees = '/employees';
  static const String employeeDetail = '/employees/detail';

  AppRoutes._();
}
