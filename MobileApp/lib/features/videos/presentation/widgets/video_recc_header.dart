import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_close_button.dart';

/// Top-of-screen header for [VideoReccScreen] — a centered title with
/// a close (X) action on the right. Mirrors the Figma `VideoRecc` frame
/// header pattern.
class VideoReccHeader extends StatelessWidget {
  const VideoReccHeader({
    super.key,
    required this.title,
    required this.onClose,
  });

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          title,
          style: DesignConstants.h1,
          textAlign: TextAlign.center,
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: AppCloseButton(onTap: onClose),
        ),
      ],
    );
  }
}
