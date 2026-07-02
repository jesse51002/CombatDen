import 'package:flutter/material.dart';

/// One editable `(time, instructor)` slot draft in the class form's schedule
/// editor — the UI-only, mutable counterpart of the wire-level `ClassSlot`.
/// [time] is null until picked (a blank row the "Add time" button just
/// created); submit validation requires every active day's slots to all have
/// a picked time and no duplicates.
class SlotDraft {
  TimeOfDay? time;
  String? instructorId;

  SlotDraft({this.time, this.instructorId});
}
