import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/settings/data/repositories/reports_export_repository.dart';
import 'package:crm/features/settings/presentation/sections/all_time_report_block.dart';
import 'package:crm/features/settings/presentation/sections/full_export_block.dart';
import 'package:crm/features/settings/presentation/sections/monthly_report_block.dart';

/// Settings section: download the gym's records as CSV spreadsheets, zipped.
///
/// Three independent download actions — a per-month operational report (the
/// section's single primary action), the same report all-time, and a full raw
/// data export. Each block owns its own idle / in-flight / error state (a
/// page-scoped read, no bloc). One [ReportsExportRepository] is provided here
/// so all three share a single client.
class ReportsExportsSection extends StatelessWidget {
  const ReportsExportsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<ReportsExportRepository>(
      create: (_) => ReportsExportRepository(apiClient: ApiClient()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text('Reports & exports', style: DesignConstants.h1),
              Text(
                'Download your gym\'s records as CSV spreadsheets, zipped and '
                'ready for Excel or Google Sheets.',
                style:
                    DesignConstants.p.copyWith(color: DesignConstants.text2nd),
              ),
            ],
          ),
          const MonthlyReportBlock(),
          const AllTimeReportBlock(),
          const FullExportBlock(),
        ],
      ),
    );
  }
}
