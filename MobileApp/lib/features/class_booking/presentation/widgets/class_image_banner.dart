import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// Full-bleed hero image for the class detail screen. Height matches the
/// design frame (248px) and the network image is rendered with
/// [BoxFit.cover].
class ClassImageBanner extends StatelessWidget {
  const ClassImageBanner({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 248,
      child: Image(
        image: CachedNetworkImageProvider(imageUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ColoredBox(color: DesignConstants.card),
      ),
    );
  }
}
