import 'package:flutter/widgets.dart';
import 'package:mobile_app/features/class_booking/data/mock_class_detail.dart';

/// Everything a `class_format` layout needs, gathered once so the five
/// layouts share one payload instead of repeating five parameters.
///
/// Every layout receives the SAME data and the SAME hooks. A layout may
/// change where these land and how prominent they are; it may not drop
/// one, add one, or reach for anything not in here — which is what
/// keeps a format an ARRANGEMENT and not a different screen.
///
/// [captureController], [imageKey] and [reserveKey] are the dev capture
/// harness's hooks (`tools/capture/`), null in normal app use. Every
/// layout must still attach them: the controller to its scrolling body,
/// the image key around the class photo, the reserve key around the
/// CTA. The `ClassKeyedBanner` / `ClassKeyedReserve` parts exist so no
/// layout has to remember the last two.
class ClassLayoutData {
  const ClassLayoutData({
    required this.detail,
    required this.onReserve,
    this.captureController,
    this.imageKey,
    this.reserveKey,
  });

  final MockClassDetail detail;
  final VoidCallback onReserve;
  final ScrollController? captureController;
  final GlobalKey? imageKey;
  final GlobalKey? reserveKey;
}
