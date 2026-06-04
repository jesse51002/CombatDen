import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/navigation/app_routes.dart';

/// Browser-URL syncing for the authenticated app's **nested** [Navigator].
///
/// All section navigation runs inside the nested navigator built in the auth
/// gate's `_MembersWorkspace`. In Flutter web only the *root* navigator syncs to
/// the browser address bar, so without this the URL never changes after the
/// first load (deep-link-on-refresh works, but in-session nav doesn't show in
/// the bar). [UrlSyncObserver] watches the nested navigator and reflects the
/// current top-level section into the URL; [MemberAppScreen] also calls
/// [syncBrowserUrl] directly when the user switches its tabs (a `setState`, not
/// a route push, so the observer can't see it).
///
/// The deliberate **hash** URL strategy is kept (no `usePathUrlStrategy`); under
/// it [SystemNavigator.routeInformationUpdated] writes the fragment
/// (`…/#/schedule`). It only *reports* the location to the browser — it does not
/// re-invoke routing — so there's no navigation feedback loop. Browser
/// Back/Forward is intentionally not wired (see `CRM/CLAUDE.md`).

/// The top-level section routes whose URL should appear in the address bar.
/// Detail / form sub-routes (member detail, class form) deliberately stay at
/// their parent section's URL — they read route arguments and aren't
/// deep-linkable today, so surfacing their URL would invite a broken refresh.
const Set<String> kAddressableRoutes = {
  AppRoutes.home,
  AppRoutes.members,
  AppRoutes.schedule,
  AppRoutes.growth,
  AppRoutes.employees,
  AppRoutes.qrCodes,
  AppRoutes.memberAppPreview,
  AppRoutes.memberAppPreviewVideos,
  AppRoutes.memberAppPreviewLoyalty,
};

/// Reflect [routeName] into the browser address bar (the fragment, under the
/// hash strategy). `replace: true` keeps a single history entry so a stray
/// half-wired Back never appears.
void syncBrowserUrl(String routeName) {
  SystemNavigator.routeInformationUpdated(
    uri: Uri.parse(routeName),
    replace: true,
  );
}

/// Updates the browser URL whenever the nested navigator's top route changes to
/// an addressable section.
class UrlSyncObserver extends NavigatorObserver {
  UrlSyncObserver();

  void _sync(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null) return;
    if (kAddressableRoutes.contains(Uri.parse(name).path)) {
      syncBrowserUrl(name);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _sync(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _sync(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _sync(previousRoute);
}
