import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_layout_data.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_keyed_banner.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_keyed_reserve.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_screen_topbar.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_tab_bar.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_details_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_image_banner.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_instructor_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_location_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_meta_section.dart';

const List<String> _kTabs = ['Details', 'Instructor', 'Location'];

/// The flick speed that turns a drag into a tab change. Matches the
/// screen's own swipe threshold so the two read as one gesture family.
const double _kSwipeVelocity = 50;

/// `ClassFormat.sectionTabs` — photo and meta stay put, the three
/// sections share one swipeable pane.
///
/// Takes the scroll out of the decision: what the class is and when it
/// runs is always on screen. The cost is that two thirds of the detail
/// now sits behind a tap — and that a horizontal drag inside the pane
/// belongs to the tabs, so the screen's swipe into the post-class flow
/// answers from the header, the tab bar and the footer instead.
///
/// The pane is an [IndexedStack], not a `PageView`: a PageView never
/// builds the pages you have not visited, which would take two of this
/// screen's sections out of the tree entirely. Hiding a section behind
/// a tab is an arrangement; dropping it is a different screen.
class ClassSectionTabs extends StatefulWidget {
  const ClassSectionTabs({super.key, required this.data});

  final ClassLayoutData data;

  @override
  State<ClassSectionTabs> createState() => _ClassSectionTabsState();
}

class _ClassSectionTabsState extends State<ClassSectionTabs> {
  int _index = 0;

  void _select(int index) {
    final next = index.clamp(0, _kTabs.length - 1);
    if (next != _index) setState(() => _index = next);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -_kSwipeVelocity) _select(_index + 1);
    if (velocity > _kSwipeVelocity) _select(_index - 1);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final detail = data.detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ClassScreenTopbar(),
        ClassKeyedBanner(data: data, treatment: ClassBannerTreatment.compact),
        Padding(
          padding: EdgeInsets.all(DesignConstants.screenHorizontalPadding),
          child: ClassMetaSection(detail: detail),
        ),
        ClassTabBar(labels: _kTabs, index: _index, onSelect: _select),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: _onDragEnd,
            child: IndexedStack(
              index: _index,
              children: [
                _Pane(
                  controller: data.captureController,
                  child: ClassDetailsSection(
                    description: detail.classData.description,
                  ),
                ),
                _Pane(
                  child: ClassInstructorSection(
                    detail: detail,
                    layout: ClassInstructorLayout.avatarTop,
                  ),
                ),
                _Pane(child: ClassLocationSection(detail: detail)),
              ],
            ),
          ),
        ),
        ClassKeyedReserve(data: data),
      ],
    );
  }
}

/// One tab's content, scrollable so a long bio or description still
/// reaches its end inside a short pane.
class _Pane extends StatelessWidget {
  const _Pane({required this.child, this.controller});

  final Widget child;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        DesignConstants.screenHorizontalPadding,
        DesignConstants.spacingBig,
        DesignConstants.screenHorizontalPadding,
        DesignConstants.spacingBig,
      ),
      child: child,
    );
  }
}
