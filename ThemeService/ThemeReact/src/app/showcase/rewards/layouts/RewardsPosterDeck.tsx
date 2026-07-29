// Ports ../../../../../../../MobileApp/lib/features/rewards/presentation/
// layouts/rewards_poster_deck.dart — `RewardsFormat.posterDeck`.
//
// Topbar, segmented tabs and the points headline pin to the top; the rest of
// the screen is a horizontally snapping deck of posters, each taking the full
// width. Fewest rewards visible at once, strongest individual reward.
//
// THE REDEEM ACTION STAYS ON THE POSTER. The proposal pinned ONE action under
// the deck to serve whichever poster was focused. Two things argue against it:
// a card that does not carry its own action breaks the one contract every
// reward card holds, and a button outside the deck is genuinely ambiguous
// mid-swipe — halfway between two posters it belongs to neither. Same element
// count per reward AND per screen, no bespoke counting rule in the gate.
//
// EVERY POSTER IS BUILT UP FRONT, exactly as the Dart's non-lazy `Row` does. A
// virtualised deck would leave most of the store unmounted, which is precisely
// the kind of quiet disappearance the invariant test exists to catch.
//
// THE SNAP IS CSS, NOT STATE. `scroll-snap-type` + `scroll-snap-align` do what
// Dart's `PageScrollPhysics` does, with no controller, no scroll listener and
// no `setState` — which is not merely tidier here, it is required: the React
// Compiler's `set-state-in-effect` rule is fatal in this package
// (../../../CLAUDE.md), and a JS-driven pager is exactly the shape it forbids.

import { PointsHeadline } from '../PointsHeadline';
import { RewardCard } from '../RewardCard';
import type { RewardsLayoutData } from '../rewardsLayoutData';
import { RewardsTabs } from '../RewardsTabs';
import { RewardsTopbar } from '../RewardsTopbar';

import styles from './RewardsPosterDeck.module.css';
import stack from './rewardsStack.module.css';

export interface RewardsPosterDeckProps {
  data: RewardsLayoutData;
}

export function RewardsPosterDeck({ data }: RewardsPosterDeckProps) {
  return (
    <div className={stack.pinnedStack} data-rewards-format="posterDeck">
      <RewardsTopbar data={data} />
      <RewardsTabs active="pointsStore" layout="segmented" />
      <PointsHeadline points={data.totalPoints} />
      {/* `Expanded(child: _PosterDeck)`. */}
      <div className={styles.deck}>
        {data.items.map((item, index) => (
          // `SizedBox(width: constraints.maxWidth) > Padding(horizontal:
          // screenHorizontalPadding)` — the page's own gutter, not a gap
          // between pages, which is why it is padding rather than a deck gap.
          <div className={styles.page} key={`${String(index)}-${item.title}`}>
            <RewardCard item={item} buttonText="Redeem" layout="poster" />
          </div>
        ))}
      </div>
    </div>
  );
}
