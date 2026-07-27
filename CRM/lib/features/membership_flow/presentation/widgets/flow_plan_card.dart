import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/domain/plan_labels.dart';

/// One plan, as a card: the 16:9 hero the whole app draws a plan with, then
/// the name, the one rule line, and the price.
///
/// The shipped `ClassCard` recipe at the surface's own scale, with the
/// selected state painted OVER the content so picking one can never shift the
/// grid under a finger.
///
/// A [blocked] card is closed, not missing: dimmed, tagged over its hero, and
/// with no select mark — it can never become the pick. It stays TAPPABLE on
/// purpose, so the tap opens the answer instead of a greyed-out dead end (the
/// rules are `domain/plan_rules.dart`'s gates; what the tap OPENS is the
/// host's, since the kiosk's popup carries an auto-return countdown the desk
/// has no use for). ONE blocked visual, two labels: only [blockedLabel] varies
/// by reason, because the consequence is identical either way.
class FlowPlanCard extends StatelessWidget {
  final MembershipPlanResponse plan;
  final bool selected;

  /// This plan is closed to the person picking. Renders blocked, and its tap
  /// explains rather than selects.
  final bool blocked;

  /// The tag pinned over a blocked card's hero. The caller passes the GATE's
  /// own reason (`domain/plan_rules.dart`), so the tag and whatever the tap
  /// opens can never disagree about why; null falls back to the surface's own
  /// wording.
  final String? blockedLabel;

  final VoidCallback onTap;

  const FlowPlanCard({
    super.key,
    required this.plan,
    required this.selected,
    required this.onTap,
    this.blocked = false,
    this.blockedLabel,
  });

  @override
  Widget build(BuildContext context) {
    final copy = MembershipFlowTheme.copyOf(context);
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
            // Overlaid, not laid out: toggling the pick never reflows the card.
            if (selected)
              const Positioned.fill(child: _SelectedBorder()),
            // Top-LEFT: the top-right corner belongs to the select mark.
            if (blocked)
              Positioned(
                top: DesignConstants.spacingMedium,
                left: DesignConstants.spacingMedium,
                child: _BlockedTag(
                  label: blockedLabel ?? copy.planBlockedTag,
                ),
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

/// How far a blocked card is faded: enough to read as spent at 2m, not so far
/// that its name and price stop being legible.
const double _blockedOpacity = 0.45;

/// The blocked mark, on a scrim so it survives any hero photo.
class _BlockedTag extends StatelessWidget {
  final String label;

  const _BlockedTag({required this.label});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
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
        child: Text(label, style: scale.tag),
      ),
    );
  }
}

/// The plan's catalogue image, pinned to 16:9 so a portrait photo can never
/// make its card taller than its neighbours. A missing or broken URL degrades
/// to the placeholder rather than collapsing the card.
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

/// Name, rule, price — the order the question is asked in.
class _Body extends StatelessWidget {
  final MembershipPlanResponse plan;

  const _Body({required this.plan});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          plan.planName,
          style: scale.statement,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          planAllowanceLabel(plan),
          style: scale.caption.copyWith(
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

/// The price, rendered only through the shared money helper — minor units are
/// never divided at a call site.
class _Price extends StatelessWidget {
  final MembershipPlanResponse plan;

  const _Price({required this.plan});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final price = plan.activePrice;
    if (price == null) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          formatMinorUnits(price.price, currency: 'USD'),
          style: scale.metric,
        ),
        Flexible(
          child: Text(
            planPriceSuffix(plan),
            style: scale.caption.copyWith(
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

/// The picked-state mark: a filled sapphire disc with the tick, or a quiet ring
/// when unpicked. It sits on the photo, so the ring carries `onAccent` ink that
/// stays legible over any image.
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
