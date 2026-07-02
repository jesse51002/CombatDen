import 'package:crm/features/schedule/data/models/gym_class_response.dart';

/// Fallback label for an assigned instructor whose resolved name is missing
/// (the id is still real; only the joined `gym_employees` name came back null).
const String _kUnnamedInstructor = 'Instructor';

/// One selectable instructor for the class form's per-slot picker.
///
/// There is no GET-employees endpoint, so the form has no live staff roster to
/// pull from. Instead the picker is sourced from the **real** instructor
/// (id, name) pairs already resolved on the gym's existing classes — every
/// slot's `instructor_id` carries the joined `instructor_name` on
/// [GymClassResponse.weekdaySlots]. This keeps the ids real (no mock UUIDs the
/// backend would reject) at the cost of only listing instructors already
/// assigned somewhere; a brand-new gym with no classes yet shows an empty
/// picker (instructors are optional, so the class still saves).
class InstructorOption {
  final String id;
  final String name;

  const InstructorOption({required this.id, required this.name});

  /// Distinct instructors across [classes], sorted by name. Any id assigned on
  /// a class's slot is included (so an edited class's current instructors are
  /// always pickable), preferring a real name over the [_kUnnamedInstructor]
  /// fallback.
  static List<InstructorOption> fromClasses(List<GymClassResponse> classes) {
    final byId = <String, String>{};
    for (final c in classes) {
      for (final slots in c.weekdaySlots.values) {
        for (final slot in slots) {
          _add(byId, slot.instructorId, slot.instructorName);
        }
      }
    }
    final options = byId.entries
        .map((e) => InstructorOption(id: e.key, name: e.value))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return options;
  }

  static void _add(Map<String, String> byId, String? id, String? name) {
    if (id == null) return;
    final resolved =
        (name != null && name.trim().isNotEmpty) ? name.trim() : null;
    final existing = byId[id];
    // Keep the first real name we see; only overwrite the fallback.
    if (existing == null || existing == _kUnnamedInstructor) {
      byId[id] = resolved ?? _kUnnamedInstructor;
    }
  }
}
