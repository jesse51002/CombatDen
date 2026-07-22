import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';

/// Placeholder for a cell the backend has no value for. Never `0`, never
/// the string "null" — an absent number and a zero are different facts.
const String kEmptyCell = '—';

/// Column widths by type: names get the fill column, numbers get just
/// enough to read.
double minWidthFor(MemberListColumnType type) => switch (type) {
      MemberListColumnType.text || MemberListColumnType.unknown => 160,
      MemberListColumnType.number => 96,
      MemberListColumnType.cents => 112,
      MemberListColumnType.date => 128,
    };

/// Numbers and money read right-aligned so their digits line up.
bool isNumericColumn(MemberListColumnType type) =>
    type == MemberListColumnType.number || type == MemberListColumnType.cents;

/// Renders one positional cell against its column's declared type.
///
/// A cell arrives as a `String`, a `double`, or null. A null renders as an
/// em-dash; a value whose runtime type does not match its column falls back
/// to its plain string form rather than throwing — one odd cell must not
/// take the page down.
Widget buildMemberListCell(Object? value, MemberListColumnType type) {
  if (value == null) return _cellText(kEmptyCell, muted: true, align: type);
  switch (type) {
    case MemberListColumnType.number:
      return _cellText(
        value is double
            ? NumberFormat.decimalPattern().format(value)
            : '$value',
        align: type,
      );
    case MemberListColumnType.cents:
      return _cellText(
        value is double
            ? formatMinorUnits(value.round(), decimalDigits: 0)
            : '$value',
        align: type,
      );
    case MemberListColumnType.date:
      final parsed = value is String ? DateTime.tryParse(value) : null;
      if (parsed == null) return _cellText('$value', align: type);
      return Tooltip(
        message: DateFormat.yMMMd().format(parsed.toLocal()),
        child: _cellText(relativeDay(parsed.toLocal()), muted: true, align: type),
      );
    case MemberListColumnType.text:
    case MemberListColumnType.unknown:
      return _cellText('$value', align: type);
  }
}

Widget _cellText(
  String text, {
  bool muted = false,
  required MemberListColumnType align,
}) {
  final child = Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: isNumericColumn(align) ? TextAlign.right : TextAlign.left,
    style: muted
        ? DesignConstants.h3.copyWith(color: DesignConstants.text2nd)
        : DesignConstants.h3,
  );
  // The shared table left-aligns every cell; a numeric cell claims the full
  // column width and right-aligns its own text inside it.
  return isNumericColumn(align)
      ? SizedBox(width: double.infinity, child: child)
      : child;
}

/// `Today` / `Yesterday` / `N days ago` / `in N days`.
String relativeDay(DateTime date, {DateTime? now}) {
  final today = _dayOf(now ?? DateTime.now());
  final days = _dayOf(date).difference(today).inDays;
  if (days == 0) return 'Today';
  if (days == -1) return 'Yesterday';
  if (days == 1) return 'Tomorrow';
  if (days < 0) return '${-days} days ago';
  return 'in $days days';
}

DateTime _dayOf(DateTime value) =>
    DateTime(value.year, value.month, value.day);
