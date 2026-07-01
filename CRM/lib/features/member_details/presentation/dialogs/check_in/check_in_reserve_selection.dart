import 'package:equatable/equatable.dart';

import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// Which mutation a picked occurrence in the "Check in / Reserve" dialog
/// drives: a real (possibly retroactive) attendance record, or a reservation
/// (sign-up) for a not-yet-started occurrence.
enum CheckInReserveAction { checkIn, reserve }

/// One picked occurrence + the action to run on it. A class starting within
/// the check-in window appears in BOTH the Check-in and Reserve sections of
/// the check-in/reserve dialog (intentional overlap), so the action must
/// travel WITH the pick rather than be inferred afterward from the instance
/// alone.
class CheckInReserveSelection extends Equatable {
  final EffectiveClassInstance instance;
  final CheckInReserveAction action;

  const CheckInReserveSelection({
    required this.instance,
    required this.action,
  });

  @override
  List<Object?> get props => [instance, action];
}
