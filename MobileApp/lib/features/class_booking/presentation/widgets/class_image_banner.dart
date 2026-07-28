import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// How a layout sizes and places the class photo.
///
/// Every value renders the SAME image from the SAME url. This is size
/// and shape only: no `class_format` drops the photo — `specBrief`
/// shrinks it to a thumb beside the title rather than removing it.
enum ClassBannerTreatment {
  /// Full-width strip, 248 tall. Ships today.
  banner,

  /// The same strip, shortened so a fixed header still leaves room for
  /// the content below it.
  compact,

  /// A tall 4:5 hero that the meta block sits on top of.
  hero,

  /// Fills whatever box it is given — a full-screen backdrop.
  backdrop,

  /// A small rounded square, inline with the title.
  thumb,
}

const double _kBannerHeight = 248;
const double _kCompactHeight = 160;
const double _kThumbSize = 96;
const double _kHeroRatio = 4 / 5;

/// The class photo for the class detail screen. Rendered with
/// [BoxFit.cover] at whatever size [treatment] asks for.
class ClassImageBanner extends StatelessWidget {
  const ClassImageBanner({
    super.key,
    required this.imageUrl,
    this.treatment = ClassBannerTreatment.banner,
  });

  final String imageUrl;
  final ClassBannerTreatment treatment;

  @override
  Widget build(BuildContext context) {
    final image = Image(
      image: CachedNetworkImageProvider(imageUrl),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => ColoredBox(color: DesignConstants.card),
    );

    return switch (treatment) {
      ClassBannerTreatment.banner => SizedBox(
        width: double.infinity,
        height: _kBannerHeight,
        child: image,
      ),
      ClassBannerTreatment.compact => SizedBox(
        width: double.infinity,
        height: _kCompactHeight,
        child: image,
      ),
      ClassBannerTreatment.hero => AspectRatio(
        aspectRatio: _kHeroRatio,
        child: image,
      ),
      ClassBannerTreatment.backdrop => SizedBox.expand(child: image),
      ClassBannerTreatment.thumb => ClipRRect(
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        child: SizedBox(
          width: _kThumbSize,
          height: _kThumbSize,
          child: image,
        ),
      ),
    };
  }
}
