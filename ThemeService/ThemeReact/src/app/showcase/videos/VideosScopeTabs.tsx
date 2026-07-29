// Ports ../../../../../../MobileApp/lib/features/videos/presentation/layouts/
// videos_scope_tabs.dart — the top-filter pills, wired to the arrangement
// payload.
//
// Every arrangement goes through this rather than wiring ./VideoCategoryTabs.tsx
// itself, so the filter behaves identically in all five and only its AXIS
// changes. Without it each arrangement would be free to hand the tabs a
// different label list, which is precisely the drift the invariant forbids.

import type { VideoCategoryTabsAxis } from './VideoCategoryTabs';
import { VideoCategoryTabs } from './VideoCategoryTabs';
import type { VideosLayoutData } from './videosLayoutData';

export interface VideosScopeTabsProps {
  data: VideosLayoutData;
  axis?: VideoCategoryTabsAxis | undefined;
}

export function VideosScopeTabs({ data, axis = 'horizontal' }: VideosScopeTabsProps) {
  return (
    <VideoCategoryTabs tabs={data.tabLabels} selectedIndex={data.selectedTabIndex} axis={axis} />
  );
}
