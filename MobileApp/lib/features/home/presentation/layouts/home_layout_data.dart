import 'package:mobile_app/features/class_booking/data/class_info.dart';

/// Which of the four things the schedule can be showing right now.
enum HomeScheduleState { loading, error, empty, loaded }

/// Everything a home layout needs, gathered once so the five layouts
/// share one payload instead of each re-deriving it.
///
/// Every layout receives the SAME data and must render every element it
/// implies. A layout may move them and change their prominence; it may
/// not drop one, add one, or reach for anything not in here — there is
/// no repository, no fetch and no clock behind this class, which is what
/// makes "no variant reaches data the shipped screen did not have"
/// structurally true rather than argued.
class HomeLayoutData {
  const HomeLayoutData({
    required this.classes,
    required this.booked,
    this.hasError = false,
  });

  /// The gym's classes. Null while the fetch is in flight.
  final List<ClassInfo>? classes;

  /// The booked page of the home pager. Carries the upcoming-sessions
  /// card, the schedule title, and the per-class booked marks. This is
  /// the pre-existing state split between the two home pages, NOT an
  /// arrangement choice — no format may add or remove it.
  final bool booked;

  final bool hasError;

  /// Error wins over loading, and loading over empty — the same order
  /// the shipped bodies resolved these in.
  HomeScheduleState get state {
    if (hasError) return HomeScheduleState.error;
    final loaded = classes;
    if (loaded == null) return HomeScheduleState.loading;
    if (loaded.isEmpty) return HomeScheduleState.empty;
    return HomeScheduleState.loaded;
  }

  bool get hasSchedule => state == HomeScheduleState.loaded;

  List<ClassInfo> get loadedClasses => classes ?? const [];
}
