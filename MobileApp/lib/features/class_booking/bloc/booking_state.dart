import 'package:equatable/equatable.dart';

import 'package:mobile_app/features/class_booking/data/booking_rejection.dart';

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
    this.rejection = BookingRejection.unknown,
    this.reserveSuccessToken = 0,
    this.cancelSuccessToken = 0,
  });

  /// Live reservation state — seeded from the board's booked flag, confirmed
  /// against the member's own reservations on mount, then flipped by a
  /// successful reserve / cancel.
  final bool booked;
  final BookingStatus status;
  final String? errorMessage;

  /// Why the backend refused the last mutation, classified from its
  /// machine-readable `code` — NEVER from the message text. [errorMessage]
  /// is the prose for the member; this is what code branches on.
  final BookingRejection rejection;

  final int reserveSuccessToken;
  final int cancelSuccessToken;

  /// The last error was specifically a full class — drives the designed
  /// "Class is full" inline state (distinct from a generic backend error).
  /// Derived from the code, so rewording the backend's message can never
  /// switch it on or off.
  bool get fullClass => rejection == BookingRejection.classFull;

  bool get isBusy =>
      status == BookingStatus.reserving || status == BookingStatus.cancelling;

  /// True until the member has actually reserved or cancelled on this screen.
  /// The mount-time reservation confirm only applies while this holds, so a
  /// slow read can never overwrite a mutation the member just made.
  bool get isUntouched =>
      !isBusy && reserveSuccessToken == 0 && cancelSuccessToken == 0;

  BookingState copyWith({
    bool? booked,
    BookingStatus? status,
    String? errorMessage,
    BookingRejection? rejection,
    int? reserveSuccessToken,
    int? cancelSuccessToken,
    bool clearError = false,
  }) {
    return BookingState(
      booked: booked ?? this.booked,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      rejection: clearError
          ? BookingRejection.unknown
          : (rejection ?? this.rejection),
      reserveSuccessToken: reserveSuccessToken ?? this.reserveSuccessToken,
      cancelSuccessToken: cancelSuccessToken ?? this.cancelSuccessToken,
    );
  }

  @override
  List<Object?> get props => [
        booked,
        status,
        errorMessage,
        rejection,
        reserveSuccessToken,
        cancelSuccessToken,
      ];
}
