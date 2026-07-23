import 'package:equatable/equatable.dart';

import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/models/upcoming_session.dart';

enum HomeStatus { initial, loading, loaded, error }

/// The single state of [HomeBloc]: the joined schedule board + open
/// reservations for the loaded window.
class HomeState extends Equatable {
  const HomeState({
    this.status = HomeStatus.initial,
    this.occurrences = const [],
    this.bookedKeys = const {},
    this.upcoming = const [],
    this.windowDays = initialWindowDays,
    this.isRefreshing = false,
    this.isExtending = false,
    this.errorMessage,
  });

  /// Days loaded on first fetch.
  static const int initialWindowDays = 14;

  /// Each extension adds this many days.
  static const int extendStepDays = 14;

  /// Hard ceiling on the window so a long scroll can't fetch unboundedly.
  static const int maxWindowDays = 60;

  final HomeStatus status;

  /// The board occurrences across the window (all days, sorted).
  final List<ClassOccurrence> occurrences;

  /// Slot keys (`classId|originalDate|originalTime`) the member has reserved —
  /// an occurrence is `booked` when its [ClassOccurrence.slotKey] is in here.
  final Set<String> bookedKeys;

  /// Open reservations, soonest first (drives the upcoming-sessions card).
  final List<UpcomingSession> upcoming;

  final int windowDays;

  /// Pull-to-refresh in flight (content stays on screen).
  final bool isRefreshing;

  /// A window extension is in flight (guards against re-dispatching).
  final bool isExtending;

  final String? errorMessage;

  bool get canExtend => windowDays < maxWindowDays;

  bool isBooked(ClassOccurrence occ) => bookedKeys.contains(occ.slotKey);

  HomeState copyWith({
    HomeStatus? status,
    List<ClassOccurrence>? occurrences,
    Set<String>? bookedKeys,
    List<UpcomingSession>? upcoming,
    int? windowDays,
    bool? isRefreshing,
    bool? isExtending,
    String? errorMessage,
    bool clearError = false,
  }) {
    return HomeState(
      status: status ?? this.status,
      occurrences: occurrences ?? this.occurrences,
      bookedKeys: bookedKeys ?? this.bookedKeys,
      upcoming: upcoming ?? this.upcoming,
      windowDays: windowDays ?? this.windowDays,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isExtending: isExtending ?? this.isExtending,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        occurrences,
        bookedKeys,
        upcoming,
        windowDays,
        isRefreshing,
        isExtending,
        errorMessage,
      ];
}
