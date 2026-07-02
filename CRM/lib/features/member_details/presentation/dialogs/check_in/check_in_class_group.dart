import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// One CLASS's identity, plus every occurrence of it present in the check-in/
/// reserve dialog's loaded window — the identity-level unit the "Reserve" and
/// "Check into a past class" pickers show one card for. [occurrences] carries
/// its own order from the caller (most-recent-first for a past group,
/// soonest-first for a reservable one), so [representative] — the group's
/// first occurrence — is always the one worth captioning the card with.
class CheckInClassGroup {
  final String classId;
  final String className;
  final String? imageUrl;
  final List<EffectiveClassInstance> occurrences;

  const CheckInClassGroup({
    required this.classId,
    required this.className,
    required this.imageUrl,
    required this.occurrences,
  });

  EffectiveClassInstance get representative => occurrences.first;
}

/// Groups a (pre-sorted) instance list by class, preserving each class's
/// first-seen position — so grouping a soonest-first list yields
/// soonest-class-first groups, and grouping a most-recent-first list yields
/// most-recent-class-first groups, with no re-sort needed.
List<CheckInClassGroup> groupInstancesByClass(
  List<EffectiveClassInstance> instances,
) {
  final order = <String>[];
  final byClassId = <String, List<EffectiveClassInstance>>{};
  for (final i in instances) {
    final bucket = byClassId[i.classId];
    if (bucket == null) {
      order.add(i.classId);
      byClassId[i.classId] = [i];
    } else {
      bucket.add(i);
    }
  }
  return [
    for (final classId in order)
      CheckInClassGroup(
        classId: classId,
        className: byClassId[classId]!.first.className,
        imageUrl: byClassId[classId]!.first.imageUrl,
        occurrences: byClassId[classId]!,
      ),
  ];
}
