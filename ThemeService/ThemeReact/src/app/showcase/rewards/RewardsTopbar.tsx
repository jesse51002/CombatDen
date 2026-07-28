// Ports ../../../../../../MobileApp/lib/features/rewards/presentation/layouts/
// rewards_topbar.dart — the points store's topbar, built from
// ./rewardsLayoutData.ts so every arrangement passes the identical arguments.
//
// Its OWN arrangement is the tenant's `app_shell_format` decision, not this
// screen's — which is exactly why it is one component rather than five call
// sites that could drift apart.

import { ShowcaseTopbar } from '../support/ShowcaseTopbar';

import type { RewardsLayoutData } from './rewardsLayoutData';

export interface RewardsTopbarProps {
  data: RewardsLayoutData;
}

export function RewardsTopbar({ data }: RewardsTopbarProps) {
  return (
    <ShowcaseTopbar
      mode="nameOnly"
      gymName={data.gymName}
      logoSrc={data.gymLogoSrc}
      streakDays={data.streakDays}
      pointsLabel={data.pointsLabel}
      rankBadgeAsset={data.rankBadgeAsset}
    />
  );
}
