import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/core/utils/file_download.dart';
import 'package:crm/features/settings/data/repositories/reports_export_repository.dart';
import 'package:crm/features/settings/presentation/sections/report_action_button.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Sub-block 2 of Reports & exports: the same operational report across the
/// gym's whole history, in one download. Local idle / in-flight / error state
/// (a page-scoped read, no bloc); independent of the other actions.
class AllTimeReportBlock extends StatefulWidget {
  const AllTimeReportBlock({super.key});

  @override
  State<AllTimeReportBlock> createState() => _AllTimeReportBlockState();
}

class _AllTimeReportBlockState extends State<AllTimeReportBlock> {
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    final gymId = selectedGym.gymId;
    if (gymId == null) return;
    final repository = context.read<ReportsExportRepository>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final download = await repository.downloadAllTimeReport(gymId: gymId);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text('All-time report', style: DesignConstants.h3),
            Text(
              'The same report across your gym\'s whole history, in one '
              'download.',
              style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
            ),
          ],
        ),
        ReportActionButton(
          label: 'Download all-time',
          busyLabel: 'Preparing all-time…',
          busy: _busy,
          onPressed: _run,
        ),
        if (_error != null) ErrorMessage(message: _error!),
      ],
    );
  }
}
