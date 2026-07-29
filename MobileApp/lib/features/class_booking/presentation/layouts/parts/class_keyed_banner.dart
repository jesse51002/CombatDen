import 'package:flutter/material.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_layout_data.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_image_banner.dart';

/// The class photo with the capture harness's image key already
/// attached.
///
/// Every layout renders the photo through this part, so the key that
/// the harness scrolls to always wraps the image no matter where the
/// arrangement puts it.
class ClassKeyedBanner extends StatelessWidget {
  const ClassKeyedBanner({
    super.key,
    required this.data,
    required this.treatment,
  });

  final ClassLayoutData data;
  final ClassBannerTreatment treatment;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: data.imageKey,
      child: ClassImageBanner(
        imageUrl: data.detail.classData.imageUrl,
        treatment: treatment,
      ),
    );
  }
}
