import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/features/class_booking/data/mock_class_detail.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_details_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_image_banner.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_instructor_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_location_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_meta_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_reserve_footer.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// Class detail / booking screen.
///
/// Accepts a [MockClass] via `Navigator.pushNamed` route arguments and
/// falls back to the canonical Muay Thai sample if none is provided.
class ClassScreen extends StatelessWidget {
  const ClassScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final classData = args is MockClass ? args : fallbackClass;
    final detail = detailFor(classData);
    final gym = mockGym;

    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity;
          if (velocity != null && velocity < -50) {
            Navigator.of(
              context,
            ).pushReplacementNamed(AppRoutes.postClassStreak);
          }
        },
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTopbar(
                mode: AppTopbarMode.nameOnly,
                showBackButton: true,
                gymName: gym.name,
                logoAsset: gym.logoAsset,
                streakDays: gym.streakDays,
                pointsLabel: gym.pointsLabel,
                rankBadgeAsset: gym.rankBadgeAsset,
              ),
              ClassImageBanner(imageUrl: classData.imageUrl),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DesignConstants.spacingBig,
                children: [
                  _Body(detail: detail),
                  ClassReserveFooter(
                    onReserve: () => Navigator.of(
                      context,
                    ).pushReplacementNamed(AppRoutes.reservingLoading),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.detail});

  final MockClassDetail detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        DesignConstants.screenHorizontalPadding,
        DesignConstants.spacingBig,
        DesignConstants.screenHorizontalPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingBig,
        children: [
          ClassMetaSection(detail: detail),
          const SectionDivider(),
          ClassDetailsSection(description: detail.classData.description),
          const SectionDivider(),
          ClassInstructorSection(detail: detail),
          const SectionDivider(),
          ClassLocationSection(detail: detail),
        ],
      ),
    );
  }
}
