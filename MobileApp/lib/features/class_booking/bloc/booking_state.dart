import 'package:equatable/equatable.dart';

enum BookingStatus { idle, reserving, cancelling, error }

/// The single state of [BookingBloc] for one class occurrence.
///
/// [reserveSuccessToken] / [cancelSuccessToken] are monotonic counters the
/// screen watches to fire a one-shot terminal step (navigate to the booked
/// screen / show the cancelled confirmation) — the every-mutation-ends-in-a-
/// visible-confirmation rule.
class BookingState extends Equatable {
  const BookingState({
    required this.booked,
    this.status = BookingStatus.idle,
    this.errorMessage,
    this.fullClass = false,
    this.reserveSuccessToken = 0,
    this.cancelSuccessToken = 0,
  });

  /// Live reservation state — seeded from the board's booked flag, flipped on a
  /// successful reserve / cancel.
  final bool booked;
  final BookingStatus status;
  final String? errorMessage;

  /// The last error was specifically a full class — drives the designed
  /// "Class is full" inline state (distinct from a generic backend error).
  final bool fullClass;

  final int reserveSuccessToken;
  final int cancelSuccessToken;

  bool get isBusy =>
      status == BookingStatus.reserving || status == BookingStatus.cancelling;

  BookingState copyWith({
    bool? booked,
    BookingStatus? status,
    String? errorMessage,
    bool? fullClass,
    int? reserveSuccessToken,
    int? cancelSuccessToken,
    bool clearError = false,
  }) {
    return BookingState(
      booked: booked ?? this.booked,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      fullClass: fullClass ?? this.fullClass,
      reserveSuccessToken: reserveSuccessToken ?? this.reserveSuccessToken,
      cancelSuccessToken: cancelSuccessToken ?? this.cancelSuccessToken,
    );
  }

  @override
  List<Object?> get props => [
        booked,
        status,
        errorMessage,
        fullClass,
        reserveSuccessToken,
        cancelSuccessToken,
      ];
}
