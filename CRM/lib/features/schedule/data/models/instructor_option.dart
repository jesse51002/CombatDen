import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';

/// Fallback label for an assigned instructor whose resolved name is missing
/// (the id is still real; only the joined `gym_employees` name came back null).
const String _kUnnamedInstructor = 'Instructor';

/// One selectable instructor for the class form's per-slot picker.
///
/// The picker is primarily sourced from the gym's real staff roster (a
/// side-read of `GET /api/v1/employees/{gym_id}` — each employee's id is a valid
/// `instructor_id`). It's then merged with the instructor (id, name) pairs
/// already resolved on the gym's existing classes, so an instructor assigned on
/// a class stays pickable even if they're no longer on the roster (a data
/// mismatch never drops an in-use instructor from an edited class). Instructors
/// are optional, so an empty picker still saves.
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
    _addClasses(byId, classes);
    return _sorted(byId);
  }

  /// The staff roster merged with any instructor already assigned on a class.
  /// [employees] leads (real names win); a class-assigned instructor not on the
  /// roster is still appended so an edited class never loses its current pick.
  static List<InstructorOption> merged(
    List<Employee> employees,
    List<GymClassResponse> classes,
  ) {
    final byId = <String, String>{};
    for (final e in employees) {
      _add(byId, e.employeeId, e.fullName);
    }
    _addClasses(byId, classes);
    return _sorted(byId);
  }

  static void _addClasses(
    Map<String, String> byId,
    List<GymClassResponse> classes,
  ) {
    for (final c in classes) {
      for (final slots in c.weekdaySlots.values) {
        for (final slot in slots) {
          _add(byId, slot.instructorId, slot.instructorName);
        }
      }
    }
  }

  static List<InstructorOption> _sorted(Map<String, String> byId) {
    return byId.entries
        .map((e) => InstructorOption(id: e.key, name: e.value))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
