import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/schedule/data/models/class_range_exception.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

final DateFormat _rangeDateLabel = DateFormat('MMM d, yyyy');

/// Shown on the occurrence screen when the viewed occurrence is cancelled by
/// a RANGE exception (`entry.cancellingRangeId != null`) — a self-contained
/// side read (mirrors `ClassAttendeeRoster`'s own-repository pattern) that
/// fetches the class's range exceptions and finds the one governing this
/// occurrence, then labels it "Cancelled by a range" with the start/end
/// dates plus Edit range / Remove range cancellation actions. Both actions
/// are owned by the parent occurrence screen (which shares its mutation
/// lifecycle + success dialog + pop-back-to-board flow with the existing
/// cancel/uncancel actions) — this widget is display-only plus the two tap
/// callbacks.
class ClassOccurrenceCancellingRangeSection extends StatefulWidget {
  final String classId;
  final String cancellingRangeId;

  /// Whether the Edit range / Remove range cancellation actions show
  /// (`canEditSchedule`: owner/admin). When false the "Cancelled by a range"
  /// info still renders, but read-only (front desk + trainer).
  final bool canEdit;
  final ValueChanged<ClassRangeException> onEdit;
  final ValueChanged<ClassRangeException> onRemove;

  const ClassOccurrenceCancellingRangeSection({
    super.key,
    required this.classId,
    required this.cancellingRangeId,
    required this.canEdit,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  State<ClassOccurrenceCancellingRangeSection> createState() =>
      _ClassOccurrenceCancellingRangeSectionState();
}

class _ClassOccurrenceCancellingRangeSectionState
    extends State<ClassOccurrenceCancellingRangeSection> {
  final ScheduleRepository _repository =
      ScheduleRepository(apiClient: ApiClient());
  late final Future<ClassRangeException?> _future = _fetch();

  Future<ClassRangeException?> _fetch() async {
    final ranges = await _repository.listRangeExceptions(widget.classId);
    for (final range in ranges) {
      if (range.exceptionId == widget.cancellingRangeId) return range;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ClassRangeException?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SubtitleSection(
            title: "This day's details",
            child: Padding(
              padding: EdgeInsets.all(DesignConstants.spacingSmall),
              child: AppSpinner(),
            ),
          );
        }
        final range = snapshot.data;
        if (snapshot.hasError || range == null) {
          // The range is gone (e.g. removed elsewhere) or failed to load —
          // nothing useful to show; the occurrence is still cancelled per
          // `entry.isCancelled`, but there's no range left to edit/remove.
          return const SizedBox.shrink();
        }
        return SubtitleSection(
          title: "This day's details",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingLarge,
            children: [
              Row(
                spacing: DesignConstants.spacingMedium,
                children: [
                  Icon(
                    Symbols.event_busy_sharp,
                    size: DesignConstants.iconSizeMedium,
                    weight: DesignConstants.iconWeight,
                    color: DesignConstants.text2nd,
                  ),
                  Expanded(
                    child: Text(
                      'Cancelled by a range: '
                      '${_rangeDateLabel.format(range.startDate)} – '
                      '${_rangeDateLabel.format(range.endDate)}',
                      style: DesignConstants.p
                          .copyWith(color: DesignConstants.text2nd),
                    ),
                  ),
                ],
              ),
              if (widget.canEdit) ...[
                const Hairline(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: DesignConstants.spacingLarge,
                    children: [
                      AppOutlineButton(
                        text: 'Remove range cancellation',
                        onPressed: () => widget.onRemove(range),
                        borderColor: DesignConstants.badRed,
                        textColor: DesignConstants.badRed,
                      ),
                      AppOutlineButton(
                        text: 'Edit range',
                        onPressed: () => widget.onEdit(range),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
