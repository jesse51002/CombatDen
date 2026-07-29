// Ports ../../../../../../CRM/lib/showcase/rewards/points_headline.dart — a
// clone of MobileApp's `PointsHeadline`: the "YOU EARNED / 3,400 / POINTS"
// hero, which is a formatted points total handed to ./SparkleHero.tsx.
//
// The Dart carries its own private `_formatPoints`; the port reads the island's
// single ../formatPoints.ts instead — see that file for why there is one rather
// than four.

import { formatThousands } from '../formatPoints';

import { SparkleHero } from './SparkleHero';

export interface PointsHeadlineProps {
  /** The member's points balance. Sample data, not a customization slot. */
  points: number;
}

export function PointsHeadline({ points }: PointsHeadlineProps) {
  return <SparkleHero top="YOU EARNED" accent={formatThousands(points)} bottom="POINTS" />;
}
