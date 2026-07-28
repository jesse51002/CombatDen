import 'package:flutter/material.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_layout_data.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_keyed_banner.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_keyed_reserve.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_screen_topbar.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_section_stack.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_details_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_image_banner.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_instructor_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_location_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_meta_section.dart';

/// `ClassFormat.bannerStack` — the arrangement that ships today.
///
/// Photo, meta, then three divided sections down one scroll, with the
/// reserve action pinned beneath it. Reproduces the previous
/// `ClassScreen` body widget for widget, so a tenant with no layout
/// slot sees no change.
class ClassBannerStack extends StatelessWidget {
  const ClassBannerStack({super.key, required this.data});

  final ClassLayoutData data;

  @override
  Widget build(BuildContext context) {
    final detail = data.detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: data.captureController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ClassScreenTopbar(),
                ClassKeyedBanner(
                  data: data,
                  treatment: ClassBannerTreatment.banner,
                ),
                ClassSectionStack(
                  sections: [
                    ClassMetaSection(detail: detail),
                    ClassDetailsSection(
                      description: detail.classData.description,
                    ),
                    ClassInstructorSection(detail: detail),
                    ClassLocationSection(detail: detail),
                  ],
                ),
              ],
            ),
          ),
        ),
        ClassKeyedReserve(data: data),
      ],
    );
  }
}
