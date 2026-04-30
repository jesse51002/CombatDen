import 'package:flutter/material.dart';

/// Full-bleed hero image for the class detail screen. Height matches the
/// Figma frame (248px) and the asset is rendered with [BoxFit.cover].
class ClassImageBanner extends StatelessWidget {
  const ClassImageBanner({super.key, required this.imageAsset});

  final String imageAsset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 248,
      child: Image.asset(imageAsset, fit: BoxFit.cover),
    );
  }
}
