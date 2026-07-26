import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';
import 'package:mobile_app/shared/widgets/topbar/gym_header.dart';
import 'package:mobile_app/shared/widgets/topbar/topbar_identity_avatar.dart';

// Width of a flank control, reserved on BOTH sides so the centred title can
// never run underneath one: the back chevron is the wider of the two
// (iconSize2xl 36 + spacingMedium 8 on each side).
const double _kFlankInset = 52;

/// Top portion of [AppTopbar] — the gym name (with an optional big logo above
/// it) flanked by single-glyph controls: the back chevron on the leading edge
/// and the member's avatar on the trailing edge.
///
/// The gym title is pure, uninterrupted brand: no chevron, no second line. The
/// person lives in the flank as [TopbarIdentityAvatar], because the topbar's
/// grammar is a centred brand block between glyph controls and a filled,
/// labelled control inside the title reads as a foreign object.
///
/// Kept in its own file purely so [AppTopbar] stays under the file-length
/// limit; only [AppTopbar] should reference it.
class TopbarHeaderSection extends StatelessWidget {
  const TopbarHeaderSection({
    super.key,
    required this.mode,
    required this.showBackButton,
    required this.gymName,
    required this.logoAsset,
    required this.onTitleTap,
    this.memberName,
    this.memberPhotoUrl,
    this.memberFirstName,
    this.memberLastName,
    this.onTitleDoubleTap,
  });

  final AppTopbarMode mode;
  final bool showBackButton;
  final String gymName;
  final String logoAsset;

  /// The selected member's display name — the avatar's accessibility label.
  /// Null/blank still renders the avatar (on its person-glyph fallback).
  final String? memberName;
  final String? memberPhotoUrl;
  final String? memberFirstName;
  final String? memberLastName;

  final VoidCallback onTitleTap;
  final VoidCallback? onTitleDoubleTap;

  @override
  Widget build(BuildContext context) {
    // The title tap stays wired as the SECONDARY path into the picker; the
    // avatar is the primary, documented entry point.
    final gymLabel = Semantics(
      button: true,
      label: 'Switch profile. $gymName',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTitleTap,
        onDoubleTap: onTitleDoubleTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kFlankInset),
          child: mode == AppTopbarMode.bigLogo
              ? GymHeader(gymName: gymName, logoAsset: logoAsset)
              : _GymNameLabel(gymName: gymName),
        ),
      ),
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        gymLabel,
        if (showBackButton)
          const Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _BackButton(),
            ),
          ),
        Positioned.fill(
          child: Align(
            // In bigLogo mode the block is 100pt tall, so the avatar rides the
            // top edge rather than floating against the middle of the logo.
            alignment: mode == AppTopbarMode.bigLogo
                ? Alignment.topRight
                : Alignment.centerRight,
            child: TopbarIdentityAvatar(
              gymName: gymName,
              memberName: memberName,
              photoUrl: memberPhotoUrl,
              firstName: memberFirstName,
              lastName: memberLastName,
            ),
          ),
        ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.spacingMedium),
        child: Icon(
          Symbols.chevron_left_sharp,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text,
          size: DesignConstants.iconSize2xl,
        ),
      ),
    );
  }
}

/// The name-only variant's brand line: the gym name alone.
class _GymNameLabel extends StatelessWidget {
  const _GymNameLabel({required this.gymName});

  final String gymName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            gymName,
            style: DesignConstants.h2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
