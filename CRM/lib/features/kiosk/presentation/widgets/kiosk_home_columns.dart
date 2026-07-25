import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_or_seam.dart';

/// One half of the kiosk home, expressed as the vertical slots
/// [KioskHomeColumns] lays out: the [head] (section title + sub-text), the
/// [body] that floats in the flexible middle (the QR tile / the search field),
/// and an optional [foot] pinned under it. Neither live half uses that foot —
/// the adopt strip spans both halves below the composition instead, so the
/// columns balance by construction — but the slot stays for a screen that
/// genuinely needs one.
class KioskHomeHalf {
  final Widget head;
  final Widget body;

  /// The block pinned below the flexible middle, or null when this half has
  /// none. The whole foot band collapses when BOTH halves leave it null.
  final Widget? foot;

  const KioskHomeHalf({
    required this.head,
    required this.body,
    this.foot,
  });
}

/// The kiosk home's two-column composition, split by a vertical "or" seam. The
/// one thing it guarantees: the two bodies are co-centred.
///
/// The halves are laid out as shared horizontal BANDS (heads, bodies, an
/// optional feet band), not as independent columns, so the QR tile and the
/// search field float in the SAME flexible band and land on the same optical
/// centre whatever either half carries — nothing is pinned to a measured
/// height (founder-approved). The feet band is OMITTED, not emptied, when
/// neither half fills it: an empty band still costs the column's spacing above
/// it, stealing height from the middle the bodies are centred in. The seam is
/// one decorative overlay across all three bands, and each band reserves its
/// exact width so the overlay lands in that gutter.
class KioskHomeColumns extends StatelessWidget {
  final KioskHomeHalf left;
  final KioskHomeHalf right;

  const KioskHomeColumns({
    super.key,
    required this.left,
    required this.right,
  });

  @override
  Widget build(BuildContext context) {
    final leftFoot = left.foot;
    final rightFoot = right.foot;
    // IntrinsicHeight gives the unbounded scroll body a height, so the middle
    // band's Expanded (and the seam's stretch) resolve against it.
    return IntrinsicHeight(
      child: Stack(
        // Pass the tight height straight through, so the band column can flex.
        fit: StackFit.passthrough,
        children: [
          // Painted first, and non-hit-testing, so the gutter never swallows
          // a tap.
          const Positioned.fill(child: IgnorePointer(child: _Seam())),
          Column(
            spacing: DesignConstants.spacingBig,
            children: [
              _Band(left: left.head, right: right.head),
              Expanded(
                child: _Band(
                  left: left.body,
                  right: right.body,
                  align: CrossAxisAlignment.center,
                ),
              ),
              // Omitted, never emptied — see the class doc.
              if (leftFoot != null || rightFoot != null)
                _Band(
                  left: leftFoot ?? const SizedBox.shrink(),
                  right: rightFoot ?? const SizedBox.shrink(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One horizontal band: the two halves' slot for this row, with the seam's
/// width reserved between them so every band lines up on the same gutter.
class _Band extends StatelessWidget {
  final Widget left;
  final Widget right;
  final CrossAxisAlignment align;

  const _Band({
    required this.left,
    required this.right,
    this.align = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: align,
      spacing: DesignConstants.spacingLarge,
      children: [
        Expanded(child: left),
        const SizedBox(width: DesignConstants.navMenuButtonSize),
        Expanded(child: right),
      ],
    );
  }
}

/// The full-height "or" seam. Equal-flex spacers put it on the block's
/// horizontal centre, which is exactly the gutter every band reserves.
class _Seam extends StatelessWidget {
  const _Seam();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Spacer(), KioskOrSeam(), Spacer()],
    );
  }
}
