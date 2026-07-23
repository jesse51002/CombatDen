import 'package:intl/intl.dart';

final DateFormat _joinedFormat = DateFormat('MMMM yyyy');

/// "March 2018" — an employee's join month, derived from their `created_at`.
/// Render-layer only: displayed in local time, never sent to the backend.
String joinedLabel(DateTime createdAt) =>
    _joinedFormat.format(createdAt.toLocal());
