import 'package:mobile_app/features/home/data/models/class_occurrence.dart';

/// Route arguments for the check-in confirm screen — the class the member
/// picked to check into. Carries only what the confirmation renders: the
/// class name and its points value.
///
/// This is the seam for kiosk Phase G: today the confirm is stub-success, but
/// the real backend check-in response (streak + points_awarded) will flow
/// through these same fields once the nonce contract lands.
class CheckinConfirmArgs {
  const CheckinConfirmArgs({
    required this.className,
    required this.pointsWorth,
  });

  /// Build the args from the picked board occurrence.
  factory CheckinConfirmArgs.fromOccurrence(ClassOccurrence occurrence) =>
      CheckinConfirmArgs(
        className: occurrence.className,
        pointsWorth: occurrence.pointsWorth,
      );

  final String className;
  final int pointsWorth;
}
