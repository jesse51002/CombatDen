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
  static const String videoDetail = '/videos/detail';
  static const String videoRecc = '/videos/recc';

  // Profile
  static const String profile = '/profile';

  // Rewards tab
  static const String myRewards = '/rewards';
  static const String pointsStore = '/rewards/store';
  static const String summary = '/rewards/summary';

  // Post-class celebration flow
  static const String postClassStreak = '/post-class/streak';
  static const String postClassWins = '/post-class/wins';
  static const String postClassPoints = '/post-class/points';
  static const String postClassRewards = '/post-class/rewards';
  static const String postClassRank = '/post-class/rank';

  AppRoutes._();
}
