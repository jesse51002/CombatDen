import 'package:flutter/material.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_layout_data.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_hero_scrim.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_keyed_banner.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_keyed_reserve.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_screen_topbar.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_section_stack.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_details_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_image_banner.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_instructor_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_location_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_meta_section.dart';

/// `ClassFormat.overlayHero` — the meta rides the photo.
///
/// A taller 4:5 hero carries the topbar at its top and the meta block
/// at its bottom, both behind a fade to the page background. The
/// instructor is promoted above the description: at a combat gym the
/// coach is the reason to book.
class ClassOverlayHero extends StatelessWidget {
  const ClassOverlayHero({super.key, required this.data});

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
                _Hero(data: data),
                ClassSectionStack(
                  sections: [
                    ClassInstructorSection(detail: detail),
                    ClassDetailsSection(
                      description: detail.classData.description,
                    ),
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

class _Hero extends StatelessWidget {
  const _Hero({required this.data});

  final ClassLayoutData data;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClassKeyedBanner(data: data, treatment: ClassBannerTreatment.hero),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ClassHeroScrim(),
        ),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ClassScreenTopbar(),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ClassMetaSection(
            detail: data.detail,
            layout: ClassMetaLayout.overlay,
          ),
        ),
      ],
    );
  }
}
