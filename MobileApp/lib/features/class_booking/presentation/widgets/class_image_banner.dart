import 'package:flutter/material.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';

/// Full-bleed hero image for the class detail screen. Height matches the
/// design frame (248px) and the asset is rendered with [BoxFit.cover].
class ClassImageBanner extends StatelessWidget {
  const ClassImageBanner({super.key, required this.imageAsset});

  final String imageAsset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 248,
      child: Image(
        image: ApiImage.classAsset(imageAsset),
        fit: BoxFit.cover,
      ),
    );
  }
}
