import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/formats/format_builder.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/core/formats/theme_layout.dart';
import 'package:mobile_app/features/class_booking/data/mock_class_detail.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_banner_stack.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_detail_sheet.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_layout_data.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_overlay_hero.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_section_tabs.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_spec_brief.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Class detail / booking screen.
///
/// Accepts a [MockClass] via `Navigator.pushNamed` route arguments and
/// falls back to the canonical Muay Thai sample if none is provided.
///
/// The arrangement is resolved from the tenant's `class_format` slot and
/// delegated to one of the layouts in `presentation/layouts/`, each of
/// which composes the same sections from `presentation/widgets/`. Every
/// layout renders the same element set — topbar, photo, meta, details,
/// instructor, location, and exactly ONE reserve action — and every
/// layout keeps the screen's hooks: the capture harness's controller and
/// keys, and the horizontal swipe into the post-class flow, which is
/// owned here so no arrangement can lose it.
class ClassScreen extends StatelessWidget {
  const ClassScreen({
    super.key,
    this.classData,
    this.captureController,
    this.imageKey,
    this.reserveKey,
    this.formatOverride,
  });

  /// Injected by the capture harness (`tools/capture/`) to render a specific
  /// class detail without a route. Falls back to the route argument (then the
  /// canonical Muay Thai sample) in normal app use.
  final MockClass? classData;

  /// Capture-only: a scroll controller for the body, a key on the class photo
  /// (to scroll the topbar off / start at the image), and a key on the reserve
  /// CTA (to centre a tap pulse on it). All null in normal app use.
  final ScrollController? captureController;
  final GlobalKey? imageKey;
  final GlobalKey? reserveKey;

  /// Forces a layout instead of resolving it from the customization.
  /// Used by the layout-invariant tests and the format preview; null in
  /// normal app use.
  final ClassFormat? formatOverride;

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final data = classData ?? (args is MockClass ? args : fallbackClass);
    final layoutData = ClassLayoutData(
      detail: detailFor(data),
      onReserve: () => Navigator.of(
        context,
      ).pushReplacementNamed(AppRoutes.reservingLoading),
      captureController: captureController,
      imageKey: imageKey,
      reserveKey: reserveKey,
    );

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
        child: FormatBuilder(builder: (context) => _layout(layoutData)),
      ),
    );
  }

  Widget _layout(ClassLayoutData data) {
    return switch (formatOverride ?? ThemeLayout.classDetail()) {
      ClassFormat.bannerStack => ClassBannerStack(data: data),
      ClassFormat.overlayHero => ClassOverlayHero(data: data),
      ClassFormat.detailSheet => ClassDetailSheet(data: data),
      ClassFormat.sectionTabs => ClassSectionTabs(data: data),
      ClassFormat.specBrief => ClassSpecBrief(data: data),
    };
  }
}
