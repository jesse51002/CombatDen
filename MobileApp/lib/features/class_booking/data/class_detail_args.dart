import 'package:mobile_app/features/home/data/models/class_occurrence.dart';

/// Route arguments for the class-detail screen — the tapped board occurrence
/// plus its current booked state (from the home board's reservation join),
/// which seeds the booking bloc.
class ClassDetailArgs {
  const ClassDetailArgs({required this.occurrence, required this.booked});

  final ClassOccurrence occurrence;
  final bool booked;
}
