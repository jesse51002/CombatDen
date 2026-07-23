/// Named routes for the prototype navigator.
///
/// Each tab root is reachable via [Navigator.pushReplacementNamed]; detail
/// screens are reachable via [Navigator.pushNamed].
class AppRoutes {
  static const String home = '/';

  // Class booking
  static const String classDetail = '/class';
  static const String reservingLoading = '/class/reserving';

  // Videos
  static const String videos = '/videos';
  static const String videoTagList = '/videos/tag';
  static const String videoRecc = '/videos/recc';

  // Profile
  static const String profile = '/profile';

  // Switch profile — re-open the "Who's training?" member picker in-app.
  static const String memberSelect = '/member-select';

  // QR check-in flow: topbar tile → scanner → pick today's class → confirm.
  static const String checkinScanner = '/checkin/scanner';
  static const String checkinPickClass = '/checkin/pick';
  static const String checkinConfirm = '/checkin/confirm';

  // Rewards tab
  static const String myRewards = '/rewards';
  static const String pointsStore = '/rewards/store';
  static const String summary = '/rewards/summary';

  // Post-class celebration flow
  static const String postClassStreak = '/post-class/streak';
  static const String postClassPoints = '/post-class/points';
  static const String postClassRewards = '/post-class/rewards';
  static const String postClassRank = '/post-class/rank';

  AppRoutes._();
}
