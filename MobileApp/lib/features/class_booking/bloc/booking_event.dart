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
