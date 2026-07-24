import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_or_seam.dart';

/// One half of the kiosk home, expressed as the vertical slots
/// [KioskHomeColumns] lays out: the [head] (section title + sub-text), the
/// [body] that floats in the flexible middle (the QR tile / the search field),
/// and an optional [foot] pinned under it.
///
/// **Neither home half carries a foot today, and that is the point.** Getting
/// the app is a property of the whole screen, not of the QR column, so the
/// adopt strip that used to sit in this slot now spans BOTH halves below the
/// composition (`kiosk_home_screen.dart`). With no foot on either side the two
/// columns balance by construction rather than by tuning one down. The slot
/// stays because the band structure is general — a screen that really does need
/// a per-column foot gets one, and [KioskHomeColumns] drops the band entirely
/// when neither half fills it.
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

/// The kiosk home's two-column composition (mockup `.home-panel` x2 split by
/// `.home-seam`) — and the one thing it guarantees: the two bodies are
/// **co-centred**.
///
/// The halves are not laid out as two independent columns. They are laid out
/// as shared horizontal BANDS — heads, bodies, and an optional feet band — so
/// the QR tile and the search field float in the *same* flexible band and
/// therefore land on the *same* optical centre, no matter what either half
/// carries below it. That is a deliberate, founder-approved departure from the
/// mockup, whose left column reserves an app-adopt block the right column has
/// nothing to answer with.
///
/// Three properties fall out of the band structure rather than from any
/// measured height, so nothing here is pinned to a pixel value:
///  * both heads sit in the first band, top-aligned to each other — the fix
///    never pushes one heading down to chase the other column;
///  * both bodies sit in the (single, flexible) middle band, centred in it;
///  * the feet band is OMITTED, not emptied, when neither half fills it — an
///    empty band still costs the column's spacing above it, which would leave a
///    reserved gap under the bodies and steal that height from the flexible
///    middle the bodies are centred in. Today neither half has a foot (the
///    adopt strip spans the screen instead), so the band is always absent on
///    the live home; it exists for any future screen that needs one.
///
/// The "or" seam is drawn ONCE across all three bands as a decorative overlay
/// (the mockup's absolutely-positioned rule), so the rule spans the whole
/// composition and its badge lands on the block's centre. Each band reserves
/// the seam's exact width in its middle, so the overlay's centred rule sits
/// precisely in that reserved gutter.
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
          // Decoration only, and painted first so no content ever sits under
          // it; IgnorePointer keeps the gutter from swallowing taps.
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
              // Omitted, never emptied — a zero-height band still costs the
              // column's spacing above it. See the class doc.
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

/// The full-height "or" seam, centred over the gutter every band reserves.
/// Equal-flex spacers put it on the block's horizontal centre — which is
/// exactly where the bands' reserved gap sits, since their two halves carry
/// equal flex and equal gaps.
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
