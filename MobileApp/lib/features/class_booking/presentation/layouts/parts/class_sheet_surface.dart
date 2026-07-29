import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_layout_data.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_keyed_reserve.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_section_stack.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_details_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_instructor_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_location_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_meta_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_reserve_footer.dart';

const double _kHandleWidth = 44;
const double _kHandleHeight = 4;

/// The `detailSheet` sheet: the reserve action at the top, then the
/// same sections the other arrangements scroll through.
///
/// The grab strip is the drag target, so a drag on the content scrolls
/// it and a drag on the strip resizes the sheet — the two never fight
/// over the same gesture.
class ClassSheetSurface extends StatelessWidget {
  const ClassSheetSurface({
    super.key,
    required this.data,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final ClassLayoutData data;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final detail = data.detail;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(DesignConstants.radiusBig),
      ),
      child: ColoredBox(
        color: DesignConstants.backgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: onDragUpdate,
              onVerticalDragEnd: onDragEnd,
              child: const _GrabHandle(),
            ),
            ClassKeyedReserve(
              data: data,
              position: ClassReservePosition.sheetTop,
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: data.captureController,
                child: ClassSectionStack(
                  sections: [
                    ClassMetaSection(detail: detail),
                    ClassDetailsSection(
                      description: detail.classData.description,
                    ),
                    ClassInstructorSection(detail: detail),
                    ClassLocationSection(detail: detail),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingMedium),
      child: Center(
        child: Container(
          width: _kHandleWidth,
          height: _kHandleHeight,
          decoration: BoxDecoration(
            color: DesignConstants.divider,
            borderRadius: BorderRadius.circular(DesignConstants.radiusCircle),
          ),
        ),
      ),
    );
  }
}
