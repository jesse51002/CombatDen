import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/remove_video_dialog.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';

/// Compact video card for the horizontal carousels: thumbnail, creator
/// avatar, title, view-count meta, an optional corner pill (e.g. "Intro
/// video"), and actions. Accepts [ImageProvider]s so it serves both
/// bundled gym uploads (AssetImage) and the live feed (NetworkImage).
///
/// [showEdit] adds an Edit action next to Remove for the gym's own
/// videos; the live feed leaves it off (a pulled video can't be edited).
class VideoTile extends StatelessWidget {
  final ImageProvider thumbnail;
  final ImageProvider avatar;
  final String title;
  final String meta;
  final String? pillLabel;
  final bool showEdit;

  const VideoTile({
    super.key,
    required this.thumbnail,
    required this.avatar,
    required this.title,
    required this.meta,
    this.pillLabel,
    this.showEdit = false,
  });

  static const double _kWidth = 280;
  static const double _kThumbHeight = 158;
  static const double _kPfpSize = 35;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kWidth,
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            _Thumbnail(image: thumbnail, pillLabel: pillLabel),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignConstants.spacingMedium,
                0,
                DesignConstants.spacingMedium,
                DesignConstants.spacingMedium,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DesignConstants.spacingMedium,
                children: [
                  _Info(avatar: avatar, title: title, meta: meta),
                  _Actions(
                    showEdit: showEdit,
                    onRemove: () => RemoveVideoDialog.show(
                      context,
                      videoTitle: title,
                      teachAgent: !showEdit,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final ImageProvider image;
  final String? pillLabel;

  const _Thumbnail({required this.image, required this.pillLabel});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: VideoTile._kThumbHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: image,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(color: DesignConstants.card),
          ),
          if (pillLabel != null)
            Positioned(
              top: DesignConstants.spacingMedium,
              left: DesignConstants.spacingMedium,
              child: _Pill(label: pillLabel!),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;

  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Text(
        label,
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.backgroundColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final ImageProvider avatar;
  final String title;
  final String meta;

  const _Info({required this.avatar, required this.title, required this.meta});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        ClipOval(
          child: Image(
            image: avatar,
            width: VideoTile._kPfpSize,
            height: VideoTile._kPfpSize,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => SizedBox(
              width: VideoTile._kPfpSize,
              height: VideoTile._kPfpSize,
              child: ColoredBox(color: DesignConstants.popup),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                title,
                style: DesignConstants.p,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                meta,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  final bool showEdit;
  final VoidCallback onRemove;

  const _Actions({required this.showEdit, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    if (!showEdit) return _RemoveButton(onPressed: onRemove);
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: AppOutlineButton(
            text: 'Edit',
            fullWidth: true,
            onPressed: () => debugPrint('TODO: edit video'),
          ),
        ),
        Expanded(child: _RemoveButton(onPressed: onRemove)),
      ],
    );
  }
}

class _RemoveButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RemoveButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: DesignConstants.redDark,
        foregroundColor: DesignConstants.text,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
      ),
      child: Text('Remove', style: DesignConstants.h3),
    );
  }
}
