import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/shared/widgets/class_row/class_card.dart';
import 'package:crm/shared/widgets/fill_grid.dart';

/// The today's-classes grid on the kiosk class pick — the same
/// `FillGrid` + `ClassCard` pattern as the member-detail check-in dialog
/// (`CheckInOccurrenceCardGrid`), so a lone class stays a half-width card
/// instead of its image ballooning. Tapping a card checks the member in
/// directly, one tap, no drill-in. The cards run at the card's KIOSK type
/// scale so class names stay larger than the screen's own subtitle at ~2m.
class KioskClassGrid extends StatelessWidget {
  final List<EffectiveClassInstance> classes;

  const KioskClassGrid({super.key, required this.classes});

  @override
  Widget build(BuildContext context) {
    return FillGrid(
      minItemWidth: 220,
      minColumns: 2,
      children: [
        for (final i in classes)
          ClassCard(
            name: i.className,
            timeLabel: classDateTimeRangeLabel(
              i.classDate,
              i.resolvedClassTime,
              i.resolvedDurationMinutes,
            ),
            imageUrl: i.imageUrl,
            pointsWorth: i.pointsWorth,
            instructorName: i.resolvedInstructorName,
            kiosk: true,
            onTap: () => context.read<KioskFlowCubit>().selectClass(i),
          ),
      ],
    );
  }
}
