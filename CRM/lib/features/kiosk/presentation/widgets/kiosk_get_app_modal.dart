import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_get_app_body.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slides.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rank_slide.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// The app-download page base URL a member's kiosk QR points at. The host/path
/// is not final, so this is the single switch — never inline it at a call site.
const String kKioskAppDownloadBaseUrl = 'https://www.combatden.net/get-app';

/// Build the app-download URL the QR encodes for [gymId].
String kioskAppDownloadUrl(String gymId) => '$kKioskAppDownloadBaseUrl/$gymId';

/// The popup surface, named so a test can assert the structural rule below.
const Key kKioskGetAppPopup = Key('kiosk-get-app-popup');

/// The member-facing "Get the app" modal — the kiosk's app-adoption funnel,
/// opened from the glance or the home adopt strip's "Get it".
///
/// ONE solid popup carrying two nested cards (founder ruling), countdown and
/// Done INSIDE that surface. Nothing scrolls and there is deliberately no
/// spanning "Welcome to {gym}" header — the gym is already named twice, and
/// the whole composition must fit the iPad viewport (see [KioskGetAppBody]).
/// The veil absorbs taps; only Done or the timer ([secondsLeft]) closes it.
/// Every showcase input was warmed ONCE at kiosk entry, so this modal never
/// fetches, and a slide whose data is absent is omitted.
class KioskGetAppModal extends StatelessWidget {
  final String gymId;
  final int secondsLeft;

  /// White-labels the app card's title. Null / empty names the app
  /// generically rather than inventing a stand-in gym.
  final String? gymName;

  /// The checked-in member's sign-in address, when known (the glance path).
  /// Null from the idle home, where step 2 then omits the address.
  final String? memberEmail;

  /// The gym's cached reward catalogue — the "Earn rewards" slide.
  final List<RewardResponse> rewards;

  /// The "Book classes" slide. Must be `KioskFlowState.showcaseClasses` (a
  /// warmed week-wide window), NEVER the check-in flow's `classes`, which is
  /// empty on the idle home and every evening. Empty omits the slide.
  final List<EffectiveClassInstance> showcaseClasses;

  /// The head of the gym's OWN curated feed — the "Watch videos" slide.
  final List<Video> videos;

  /// The gym's belt ladder — the "Track rank" slide. No member link: that
  /// slide is illustrative by design (`KioskRankSlide`). Empty omits it.
  final List<KioskRankStep> rankLadder;

  const KioskGetAppModal({
    super.key,
    required this.gymId,
    required this.secondsLeft,
    this.gymName,
    this.memberEmail,
    this.rewards = const [],
    this.showcaseClasses = const [],
    this.videos = const [],
    this.rankLadder = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        // Opaque so a veil tap is swallowed, never leaking to the glance.
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ColoredBox(
          color: DesignConstants.backgroundColor.withValues(alpha: 0.92),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(DesignConstants.paddingSmall),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: DesignConstants.dialogMaxWidthWide,
                  ),
                  // Bounded, not shrink-wrapped: the body lays the foot out
                  // first and gives the cards the rest, so it never scrolls.
                  child: SizedBox.expand(
                    child: _Popup(
                      child: KioskGetAppBody(
                        gymId: gymId,
                        gymName: gymName,
                        secondsLeft: secondsLeft,
                        memberEmail: memberEmail,
                        slides: kioskShowcaseSlides(
                          classes: showcaseClasses,
                          rewards: rewards,
                          videos: videos,
                          rankLadder: rankLadder,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The single solid surface the whole modal lives on — the kiosk idle
/// warning's popup chrome at welcome-screen width. It is what makes the modal
/// read as ONE thing that opened, not two panels floating on a veil.
class _Popup extends StatelessWidget {
  final Widget child;

  const _Popup({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: kKioskGetAppPopup,
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.popup,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: child,
    );
  }
}
