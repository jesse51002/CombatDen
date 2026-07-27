import 'package:equatable/equatable.dart';

import 'package:mobile_app/features/home/data/models/class_occurrence.dart';

enum CheckinPickClassStatus { initial, loading, loaded, error }

/// The single state of [CheckinPickClassBloc]: today's pickable class
/// occurrences (soonest first). [loaded] with an empty [occurrences] list is
/// the "No classes today" empty state — distinct from [error].
class CheckinPickClassState extends Equatable {
  const CheckinPickClassState({
    this.status = CheckinPickClassStatus.initial,
    this.occurrences = const [],
    this.errorMessage,
  });

  final CheckinPickClassStatus status;

  /// Today's occurrences the member can check into, soonest first.
  final List<ClassOccurrence> occurrences;

  final String? errorMessage;

  bool get isEmpty =>
      status == CheckinPickClassStatus.loaded && occurrences.isEmpty;

  CheckinPickClassState copyWith({
    CheckinPickClassStatus? status,
    List<ClassOccurrence>? occurrences,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CheckinPickClassState(
      status: status ?? this.status,
      occurrences: occurrences ?? this.occurrences,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, occurrences, errorMessage];
}
