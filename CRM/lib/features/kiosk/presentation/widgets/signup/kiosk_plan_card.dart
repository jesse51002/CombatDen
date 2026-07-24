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
class KioskPlanCard extends StatelessWidget {
  final MembershipPlanResponse plan;
  final bool selected;
  final VoidCallback onTap;

  const KioskPlanCard({
    super.key,
    required this.plan,
    required this.selected,
    required this.onTap,
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
            Column(
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
            // Overlaid rather than laid out, so toggling the pick never
            // reflows the card.
            if (selected)
              const Positioned.fill(child: _SelectedBorder()),
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
