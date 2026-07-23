import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';

/// Placeholder for a cell the backend has no value for. Never `0`, never
/// the string "null" — an absent number and a zero are different facts.
const String kEmptyCell = '—';

/// Numbers and money read right-aligned so their digits line up.
bool isNumericColumn(MemberListColumnType type) =>
    type == MemberListColumnType.number || type == MemberListColumnType.cents;

/// The absolute date a growth table cell shows — never relative ("N days
/// ago"). A month-granularity table (the companion tables) reads `Sep 2025`
/// (`DateFormat.yMMM`, the same month form the chart's read-out uses); a
/// day-level date (a member's "started" / "last seen") reads `Sep 5, 2026`.
String absoluteDate(DateTime date, String? granularity) =>
    granularity == 'month'
        ? DateFormat.yMMM().format(date)
        : DateFormat.yMMMd().format(date);

/// Renders one positional cell against its column's declared type.
///
/// A cell arrives as a `String`, a `double`, or null. A null renders as an
/// em-dash; a value whose runtime type does not match its column falls back
/// to its plain string form rather than throwing — one odd cell must not
/// take the page down.
///
/// [granularity] shapes how a `date` cell reads (see [absoluteDate]);
/// [toneColor], when supplied, tints a value cell's text (the companion
/// table's good/bad/warn column tones). A `date` cell is never toned — it is
/// a label column, not a value — and an absent (null) cell keeps its muted
/// em-dash regardless of tone.
Widget buildMemberListCell(
  Object? value,
  MemberListColumnType type, {
  String? granularity,
  Color? toneColor,
}) {
  if (value == null) return _cellText(kEmptyCell, muted: true, align: type);
  switch (type) {
    case MemberListColumnType.number:
      return _cellText(
        value is double
            ? NumberFormat.decimalPattern().format(value)
            : '$value',
        align: type,
        color: toneColor,
      );
    case MemberListColumnType.cents:
      return _cellText(
        value is double
            ? formatMinorUnits(value.round(), decimalDigits: 0)
            : '$value',
        align: type,
        color: toneColor,
      );
    case MemberListColumnType.date:
      final parsed = value is String ? DateTime.tryParse(value) : null;
      if (parsed == null) return _cellText('$value', align: type);
      return _cellText(
        absoluteDate(parsed.toLocal(), granularity),
        muted: true,
        align: type,
      );
    case MemberListColumnType.text:
    case MemberListColumnType.unknown:
      return _cellText('$value', align: type, color: toneColor);
  }
}

Widget _cellText(
  String text, {
  bool muted = false,
  required MemberListColumnType align,
  Color? color,
}) {
  final resolved = color ?? (muted ? DesignConstants.text2nd : null);
  final child = Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: isNumericColumn(align) ? TextAlign.right : TextAlign.left,
    style: resolved == null
        ? DesignConstants.h3
        : DesignConstants.h3.copyWith(color: resolved),
  );
  // The shared table left-aligns every cell; a numeric cell claims the full
  // column width and right-aligns its own text inside it.
  return isNumericColumn(align)
      ? SizedBox(width: double.infinity, child: child)
      : child;
}
