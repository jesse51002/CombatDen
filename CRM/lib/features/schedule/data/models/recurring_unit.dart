/// `gym_classes.recurring_unit` — how a class repeats.
///
/// Mirrors the backend `schema.gym_class.RecurringUnit` enum
/// (`daily` / `weekly` / `monthly`). Carries an [unknown] fallback so a
/// new backend value never crashes the UI (resilient enum parsing).
enum RecurringUnit {
  daily,
  weekly,
  monthly,
  unknown;

  /// Parse the lowercase backend string, falling back to [unknown].
  static RecurringUnit fromJson(String value) => RecurringUnit.values.firstWhere(
        (u) => u.name == value,
        orElse: () => RecurringUnit.unknown,
      );

  String get label {
    switch (this) {
      case RecurringUnit.daily:
        return 'Daily';
      case RecurringUnit.weekly:
        return 'Weekly';
      case RecurringUnit.monthly:
        return 'Monthly';
      case RecurringUnit.unknown:
        return 'Custom';
    }
  }
}
