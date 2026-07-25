import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_labels.dart';

/// One plan, as a card: the 16:9 hero the whole app draws a plan with, then
/// the name, the one rule line, and the price.
///
/// **It is the shipped `ClassCard` recipe at kiosk scale**, not a new object:
/// the same clipped `card` fill and `radiusSmall` corners, the same bleeding
/// 16:9 image over padded details, and the same overlay treatment for a
/// selected card (a primary outline and a check disc painted OVER the content,
/// so picking one can never shift the grid under a finger).
///
/// The check disc is the kiosk's own "selected" idiom — sapphire filled with
/// the `onAccent` tick, resting as a quiet ring so an unpicked card still
/// invites the tap.
///
/// **A [blocked] card is closed, not missing.** It is dimmed, carries a tag
/// over its hero and drops the select mark entirely — it can never become the
/// pick. It stays TAPPABLE on purpose: a greyed-out plan with no explanation is
/// a worse dead end than the one it prevents, so the tap opens the answer
/// instead of setting the selection.
///
/// **ONE blocked visual, two labels.** [blockedLabel] is the only thing that
/// varies by reason ("Already used" for a spent trial, "You have this" for a
/// membership they currently hold) — a second blocked treatment would teach a
/// member two things where the consequence is identical.
class KioskPlanCard extends StatelessWidget {
  final MembershipPlanResponse plan;
  final bool selected;

  /// This plan is closed to the person picking. Renders blocked, and its tap
  /// explains rather than selects.
  final bool blocked;

  /// The tag pinned over a blocked card's hero. Comes from
  /// `kiosk_plan_block_copy.dart`'s reason switch at the call site, so the tag
  /// and the popup behind it can never disagree about why.
  final String blockedLabel;

  final VoidCallback onTap;

  const KioskPlanCard({
    super.key,
    required this.plan,
    required this.selected,
    required this.onTap,
    this.blocked = false,
    this.blockedLabel = 'Already used',
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.primaryColor10
              : DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
        child: Stack(
          children: [
            Opacity(
              opacity: blocked ? _blockedOpacity : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DesignConstants.spacingMedium,
                children: [
                  _Hero(imageUrl: plan.imageUrl),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: DesignConstants.spacingMedium,
                      right: DesignConstants.spacingMedium,
                      bottom: DesignConstants.spacingMedium,
                    ),
                    child: _Body(plan: plan),
                  ),
                ],
              ),
            ),
            // Overlaid rather than laid out, so toggling the pick never
            // reflows the card.
            if (selected)
              const Positioned.fill(child: _SelectedBorder()),
            // Top-LEFT: the top-right corner is the select mark's, and the two
            // must never argue over the same pixel.
            if (blocked)
              Positioned(
                top: DesignConstants.spacingMedium,
                left: DesignConstants.spacingMedium,
                child: _BlockedTag(label: blockedLabel),
              )
            else
              Positioned(
                top: DesignConstants.spacingMedium,
                right: DesignConstants.spacingMedium,
                child: _SelectMark(selected: selected),
              ),
          ],
        ),
      ),
    );
  }
}

/// How far a blocked card is faded. Enough to read as spent at 2m, not so far
/// that its name and price stop being legible — the member still has to see
/// WHICH plan is the one they already used.
const double _blockedOpacity = 0.45;

/// The blocked mark, on a scrim so it survives any hero photo. It rides the
/// ramp's smallest role, which is the one reserved for a tag pinned on artwork.
class _BlockedTag extends StatelessWidget {
  final String label;

  const _BlockedTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingSmall,
        ),
        decoration: BoxDecoration(
          color: DesignConstants.backgroundColor.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
        child: Text(label, style: DesignConstants.kioskTag),
      ),
    );
  }
}

/// The plan's own catalogue image, at the app-wide 16:9 card ratio so a plan
/// with a portrait photo can never make its card taller than its neighbours.
/// A missing or broken URL degrades to the neutral placeholder rather than
/// collapsing the card.
class _Hero extends StatelessWidget {
  final String imageUrl;

  const _Hero({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: imageUrl.isEmpty
          ? const _PlaceholderHero()
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _PlaceholderHero(),
            ),
    );
  }
}

class _PlaceholderHero extends StatelessWidget {
  const _PlaceholderHero();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DesignConstants.card,
      child: Center(
        child: Icon(
          Symbols.image_sharp,
          size: DesignConstants.iconSizeBig,
          color: DesignConstants.text3rd,
          weight: DesignConstants.iconWeight,
        ),
      ),
    );
  }
}

/// Name, rule, price — in that order, because that is the order the question
/// is asked in: what is it, what do I get, what does it cost.
class _Body extends StatelessWidget {
  final MembershipPlanResponse plan;

  const _Body({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          plan.planName,
          style: DesignConstants.kioskStatement,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          kioskPlanRuleLabel(plan),
          style: DesignConstants.kioskCaption.copyWith(
            color: DesignConstants.text2nd,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        _Price(plan: plan),
      ],
    );
  }
}

/// The price, rendered ONLY through the shared money helper — the amount is
/// signed minor units end to end and is never divided at a call site.
class _Price extends StatelessWidget {
  final MembershipPlanResponse plan;

  const _Price({required this.plan});

  @override
  Widget build(BuildContext context) {
    final price = plan.activePrice;
    if (price == null) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          formatMinorUnits(price.price, currency: 'USD'),
          style: DesignConstants.kioskMetric,
        ),
        Flexible(
          child: Text(
            kioskPlanPriceSuffix(plan),
            style: DesignConstants.kioskCaption.copyWith(
              color: DesignConstants.text2nd,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SelectedBorder extends StatelessWidget {
  const _SelectedBorder();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: DesignConstants.primaryColor),
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
      ),
    );
  }
}

/// The picked-state mark: a filled sapphire disc with the tick, or a quiet
/// ring on a card that has not been picked. It sits on the photo, so the ring
/// carries the `onAccent` ink that stays legible over any image.
class _SelectMark extends StatelessWidget {
  final bool selected;

  const _SelectMark({required this.selected});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: DesignConstants.iconSizeLarge,
        height: DesignConstants.iconSizeLarge,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.primaryColor
              : DesignConstants.popup.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: selected
              ? null
              : Border.all(
                  color: DesignConstants.onAccent,
                  width: DesignConstants.buttonBorder,
                ),
        ),
        child: selected
            ? Icon(
                Symbols.check_sharp,
                size: DesignConstants.iconSizeTiny,
                color: DesignConstants.onAccent,
                weight: DesignConstants.iconWeight,
              )
            : null,
      ),
    );
  }
}
