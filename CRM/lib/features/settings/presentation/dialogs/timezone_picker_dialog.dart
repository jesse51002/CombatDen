import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_search_box.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Memoized lazy load of the full IANA timezone database (the `timezone`
/// package). First triggered when the Settings timezone control renders /
/// the picker opens — never at app startup; every later call reuses the
/// same future.
Future<void>? _tzInit;
Future<void> ensureTimezonesInitialized() =>
    _tzInit ??= Future<void>(tzdata.initializeTimeZones);

/// `UTC±HH:MM` with a proper sign and zero-padding — `UTC−05:00`,
/// `UTC+05:45`, `UTC+00:00`.
String formatUtcOffset(Duration offset) {
  final sign = offset.isNegative ? '−' : '+';
  final total = offset.abs();
  final h = total.inHours.toString().padLeft(2, '0');
  final m = total.inMinutes.remainder(60).toString().padLeft(2, '0');
  return 'UTC$sign$h:$m';
}

/// `America/Chicago (UTC−05:00)` — the offset computed from the tz database
/// at call time (so DST is respected); just the id when the zone is unknown
/// or the database isn't loaded yet.
String zoneDisplayLabel(String zoneId) {
  try {
    final offset = tz.TZDateTime.now(tz.getLocation(zoneId)).timeZoneOffset;
    return '$zoneId (${formatUtcOffset(offset)})';
  } catch (_) {
    return zoneId;
  }
}

/// One pickable zone: its IANA id, current offset (for sorting), display
/// label, and the normalized text the search filter matches against (the
/// name with `_`→space, plus the offset with an ASCII `-` so a typed
/// "-05:00" matches the label's typographic minus).
class _ZoneEntry {
  final String id;
  final Duration offset;
  final String label;
  final String searchText;

  _ZoneEntry._(this.id, this.offset, this.label, this.searchText);

  factory _ZoneEntry.of(String id) {
    final offset = tz.TZDateTime.now(tz.getLocation(id)).timeZoneOffset;
    final offsetLabel = formatUtcOffset(offset);
    final idLower = id.toLowerCase();
    return _ZoneEntry._(
      id,
      offset,
      '$id ($offsetLabel)',
      '$idLower ${idLower.replaceAll('_', ' ')} '
          '${offsetLabel.toLowerCase().replaceAll('−', '-')}',
    );
  }
}

/// Searchable picker over the FULL IANA timezone database, each entry
/// showing its current UTC offset, sorted by offset then name. [show]
/// resolves to the picked zone id, or null when dismissed.
class TimezonePickerDialog {
  TimezonePickerDialog._();

  static Future<String?> show({
    required BuildContext context,
    String? current,
  }) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Select timezone',
        expanded: true,
        body: _PickerBody(current: current),
      ),
    );
  }
}

/// Search box + the filtered, scrollable zone list. Waits on the lazy tz
/// database load (a spinner on the very first open).
class _PickerBody extends StatefulWidget {
  final String? current;

  const _PickerBody({required this.current});

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  String _query = '';

  /// Built once per open, after the database is ready — offsets are "as of
  /// now", so a fresh open reflects DST changes.
  List<_ZoneEntry>? _zones;

  List<_ZoneEntry> _allZones() {
    final entries = [
      for (final id in tz.timeZoneDatabase.locations.keys) _ZoneEntry.of(id),
    ]..sort((a, b) {
        final byOffset = a.offset.compareTo(b.offset);
        return byOffset != 0 ? byOffset : a.id.compareTo(b.id);
      });
    return entries;
  }

  List<_ZoneEntry> _filtered() {
    final all = _zones ??= _allZones();
    final q = _query.trim().toLowerCase().replaceAll('−', '-');
    if (q.isEmpty) return all;
    return [
      for (final entry in all)
        if (entry.searchText.contains(q)) entry,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: ensureTimezonesInitialized(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: AppSpinner());
        }
        final zones = _filtered();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            AppSearchBox(
              hintText: 'Search by name or UTC offset…',
              onChanged: (value) => setState(() => _query = value),
            ),
            Expanded(
              child: zones.isEmpty
                  ? Text(
                      'No timezones match “${_query.trim()}”.',
                      style: DesignConstants.pSmall.copyWith(
                        color: DesignConstants.text2nd,
                      ),
                    )
                  : _ZoneList(zones: zones, current: widget.current),
            ),
          ],
        );
      },
    );
  }
}

/// The scrollable zone rows; tapping one pops the dialog with its id.
class _ZoneList extends StatelessWidget {
  final List<_ZoneEntry> zones;
  final String? current;

  const _ZoneList({required this.zones, required this.current});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: zones.length,
      separatorBuilder: (_, _) => Divider(
        height: DesignConstants.spacingMedium,
        thickness: DesignConstants.dividerThickness,
        color: DesignConstants.divider,
      ),
      itemBuilder: (context, i) => _ZoneRow(
        entry: zones[i],
        isCurrent: zones[i].id == current,
      ),
    );
  }
}

/// One tappable zone row; the gym's current zone is tinted + check-marked.
class _ZoneRow extends StatelessWidget {
  final _ZoneEntry entry;
  final bool isCurrent;

  const _ZoneRow({required this.entry, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(entry.id),
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.spacingSmall),
        child: Row(
          spacing: DesignConstants.spacingSmall,
          children: [
            Expanded(
              child: Text(
                entry.label,
                style: DesignConstants.p.copyWith(
                  color: isCurrent
                      ? DesignConstants.primaryColor
                      : DesignConstants.text,
                ),
              ),
            ),
            if (isCurrent)
              Icon(
                Symbols.check_sharp,
                size: DesignConstants.iconSizeSmall,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.primaryColor,
              ),
          ],
        ),
      ),
    );
  }
}
