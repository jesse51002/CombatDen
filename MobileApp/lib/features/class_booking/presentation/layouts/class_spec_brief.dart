import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_layout_data.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_keyed_banner.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_keyed_reserve.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_screen_topbar.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_details_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_image_banner.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_instructor_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_location_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_meta_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_reserve_footer.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';

/// `ClassFormat.specBrief` — the facts first, the poster last.
///
/// No banner: the photo becomes a thumb inline with the title, the
/// specifics become a table, and instructor and location compress to
/// strips. The reserve action sits at the end of the content instead of
/// pinned. For the member who has taken this class fifty times and
/// wants the time and the mat.
class ClassSpecBrief extends StatelessWidget {
  const ClassSpecBrief({super.key, required this.data});

  final ClassLayoutData data;

  @override
  Widget build(BuildContext context) {
    final detail = data.detail;
    return SingleChildScrollView(
      controller: data.captureController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ClassScreenTopbar(),
          Padding(
            padding: EdgeInsets.fromLTRB(
              DesignConstants.screenHorizontalPadding,
              DesignConstants.spacingBig,
              DesignConstants.screenHorizontalPadding,
              DesignConstants.spacingBig,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingBig,
              children: [
                ClassMetaSection(
                  detail: detail,
                  layout: ClassMetaLayout.specTable,
                  leading: ClassKeyedBanner(
                    data: data,
                    treatment: ClassBannerTreatment.thumb,
                  ),
                ),
                const SectionDivider(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DesignConstants.spacingLarge,
                  children: [
                    ClassInstructorSection(
                      detail: detail,
                      layout: ClassInstructorLayout.row,
                    ),
                    ClassLocationSection(
                      detail: detail,
                      layout: ClassLocationLayout.row,
                    ),
                  ],
                ),
                const SectionDivider(),
                ClassDetailsSection(
                  description: detail.classData.description,
                ),
                ClassKeyedReserve(
                  data: data,
                  position: ClassReservePosition.inline,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
