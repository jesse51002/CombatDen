import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/core/utils/file_download.dart';
import 'package:crm/features/settings/data/repositories/reports_export_repository.dart';
import 'package:crm/features/settings/presentation/sections/report_action_button.dart';
import 'package:crm/features/settings/presentation/sections/report_period_options.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';

/// Fixed widths so the month + year pickers keep a stable size as they wrap
/// (a Wrap child needs a bounded width for the expanded dropdown to lay out).
const double _kMonthFieldWidth = 168;
const double _kYearFieldWidth = 112;

/// Sub-block 1 of Reports & exports: pick a month + year and download that
/// month's operational report. The section's single primary action. Local
/// widget state (idle / in-flight / error) — downloads are transient UI, not
/// app state, so this rides no bloc (the hybrid model's sanctioned page-scoped
/// exception).
class MonthlyReportBlock extends StatefulWidget {
  const MonthlyReportBlock({super.key});

  @override
  State<MonthlyReportBlock> createState() => _MonthlyReportBlockState();
}

class _MonthlyReportBlockState extends State<MonthlyReportBlock> {
  late int _year;
  late int _month;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  void _onYearChanged(int? year) {
    if (year == null) return;
    final max = maxMonthForYear(year, DateTime.now());
    setState(() {
      _year = year;
      // A past year opens all 12 months; the current year caps at this month,
      // so clamp a now-invalid selection back into range.
      if (_month > max) _month = max;
    });
  }

  void _onMonthChanged(int? month) {
    if (month == null) return;
    setState(() => _month = month);
  }

  Future<void> _run() async {
    final gymId = selectedGym.gymId;
    if (gymId == null) return;
    final repository = context.read<ReportsExportRepository>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final download = await repository.downloadMonthlyReport(
        gymId: gymId,
        year: _year,
        month: _month,
      );
      downloadBytes(download.bytes, download.filename);
      if (mounted) setState(() => _busy = false);
    } on DatabaseException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = reportYears(selectedGym.createdAt, now);
    final maxMonth = maxMonthForYear(_year, now);
    final month = _month.clamp(1, maxMonth);
    final monthName = kReportMonthNames[month - 1];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text('Monthly report', style: DesignConstants.h3),
            Text(
              'Financials, membership changes, and check-ins for a single '
              'month.',
              style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
            ),
          ],
        ),
        Wrap(
          spacing: DesignConstants.spacingMedium,
          runSpacing: DesignConstants.spacingMedium,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Dim + freeze only this action's pickers while it downloads; the
            // other actions stay fully usable.
            Opacity(
              opacity: _busy ? 0.5 : 1,
              child: IgnorePointer(
                ignoring: _busy,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: DesignConstants.spacingMedium,
                  children: [
                    SizedBox(
                      width: _kMonthFieldWidth,
                      child: AppDropdownField<int>(
                        key: ValueKey('month-$_year'),
                        value: month,
                        onChanged: _onMonthChanged,
                        items: [
                          for (var m = 1; m <= maxMonth; m++)
                            DropdownMenuItem(
                              value: m,
                              child: Text(kReportMonthNames[m - 1]),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: _kYearFieldWidth,
                      child: AppDropdownField<int>(
                        value: _year,
                        onChanged: _onYearChanged,
                        items: [
                          for (final y in years)
                            DropdownMenuItem(value: y, child: Text('$y')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ReportActionButton(
              primary: true,
              label: 'Download $monthName $_year',
              busyLabel: 'Preparing $monthName $_year…',
              busy: _busy,
              onPressed: _run,
            ),
          ],
        ),
        if (_error != null) ErrorMessage(message: _error!),
      ],
    );
  }
}
