import 'package:equatable/equatable.dart';

/// Events for [BookingBloc].
sealed class BookingEvent extends Equatable {
  const BookingEvent();

  @override
  List<Object?> get props => [];
}

/// Reserve the member's spot on this occurrence (POST signup).
class BookingReserveRequested extends BookingEvent {
  const BookingReserveRequested();
}

/// Cancel the member's reservation for this occurrence (DELETE signup).
class BookingCancelRequested extends BookingEvent {
  const BookingCancelRequested();
}

/// Confirm `booked` against the member's OWN reservations, rather than
/// trusting the flag whoever navigated here passed in.
///
/// Fired once when the live screen mounts. The route argument is only a seed
/// for the first frame — it is right in the common case (the board joins its
/// occurrences against the same reservations), but it is a claim made by the
/// caller, and a caller that gets it wrong shows "Reserve" for a class the
/// member already holds. This event makes the screen self-correcting so that
/// can't survive past the first read.
class BookingReservationSyncRequested extends BookingEvent {
  const BookingReservationSyncRequested();
}
