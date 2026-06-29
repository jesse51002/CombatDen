import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_curation_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Compact video card for the horizontal carousels: thumbnail, creator
/// avatar, title, view-count meta, an optional corner pill (e.g. "Intro
/// video"), and actions. Accepts [ImageProvider]s so it serves both
/// bundled gym uploads (AssetImage) and the live feed (NetworkImage).
///
/// [showEdit] adds an Edit action next to Remove for the gym's own
/// videos; the live feed leaves it off (a pulled video can't be edited).
///
/// [rejected] flips the action to a green "Keep this video" (the tile is one
/// the scan rejected, shown in the rejected section so the admin can keep it
/// back) instead of the red Remove.
///
/// [onTap] makes the thumbnail clickable — used to open the video's watch page
/// in a new browser tab. [onRemove], when given (the gym's own "Your videos"
/// feed), wires the red Remove straight to a real backend delete; without it,
/// Remove falls back to the curation dialog used by the member-preview feed.
class VideoTile extends StatelessWidget {
  // Null (or a URL that fails to load) shows NO thumbnail — no placeholder box.
  final ImageProvider? thumbnail;
  final ImageProvider avatar;
  final String title;
  final String meta;
  final String? pillLabel;
  final bool showEdit;
  final bool rejected;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const VideoTile({
    super.key,
    required this.thumbnail,
    required this.avatar,
    required this.title,
    required this.meta,
    this.pillLabel,
    this.showEdit = false,
    this.rejected = false,
    this.onTap,
    this.onRemove,
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
          children: [
            // No thumbnail → render nothing (no placeholder); the info then
            // gets its own top padding below.
            if (thumbnail != null) ...[
              _Thumbnail(
                image: thumbnail!,
                pillLabel: pillLabel,
                rejected: rejected,
                onTap: onTap,
              ),
              const SizedBox(height: DesignConstants.spacingLarge),
            ],
            Padding(
              padding: EdgeInsets.fromLTRB(
                DesignConstants.spacingMedium,
                thumbnail != null ? 0 : DesignConstants.spacingMedium,
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
                    rejected: rejected,
                    onRemove: onRemove,
                    onPrimary: () => VideoCurationDialog.show(
                      context,
                      videoTitle: title,
                      teachAgent: rejected || !showEdit,
                      mode: rejected
                          ? VideoCurationMode.keep
                          : VideoCurationMode.remove,
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
  final bool rejected;
  final VoidCallback? onTap;

  const _Thumbnail({
    required this.image,
    required this.pillLabel,
    required this.rejected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final thumb = SizedBox(
      height: VideoTile._kThumbHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: image,
            fit: BoxFit.cover,
            // A stored thumbnail that won't load (e.g. a maxres URL that 404s for
            // a non-HD video) shows nothing rather than a placeholder box.
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          // A rejected tile takes the corner marker (solid red) so it's clear
          // at a glance; otherwise show the optional content pill.
          if (rejected)
            Positioned(
              top: DesignConstants.spacingMedium,
              left: DesignConstants.spacingMedium,
              child: _Pill(
                label: 'Rejected',
                color: DesignConstants.badRed,
              ),
            )
          else if (pillLabel != null)
            Positioned(
              top: DesignConstants.spacingMedium,
              left: DesignConstants.spacingMedium,
              child: _Pill(label: pillLabel!),
            ),
        ],
      ),
    );
    if (onTap == null) return thumb;
    // Clickable thumbnail → opens the video (a new browser tab on web).
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: thumb),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color? color;

  const _Pill({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        color: color ?? DesignConstants.primaryColor,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Text(
        label,
        style: DesignConstants.pSmallBold.copyWith(
          color: DesignConstants.onAccent,
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
  final bool rejected;
  final VoidCallback onPrimary;
  final VoidCallback? onRemove;

  const _Actions({
    required this.showEdit,
    required this.rejected,
    required this.onPrimary,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (rejected) {
      // The wired action (real un-reject) when given; else the demo dialog.
      return _ActionButton(
        label: 'Keep this video',
        color: DesignConstants.goodGreen,
        onPressed: onRemove ?? onPrimary,
      );
    }
    // A real backend delete (Your videos) when wired; otherwise the
    // member-preview curation dialog.
    final removeAction = onRemove ?? onPrimary;
    if (!showEdit) {
      return _ActionButton(
        label: 'Remove',
        color: DesignConstants.badRed,
        onPressed: removeAction,
      );
    }
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
        Expanded(
          child: _ActionButton(
            label: 'Remove',
            color: DesignConstants.badRed,
            onPressed: removeAction,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: DesignConstants.onAccent,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
      ),
      // Light label for contrast on the saturated red/green fills.
      child: Text(
        label,
        style: DesignConstants.h3.copyWith(color: DesignConstants.onAccent),
      ),
    );
  }
}
