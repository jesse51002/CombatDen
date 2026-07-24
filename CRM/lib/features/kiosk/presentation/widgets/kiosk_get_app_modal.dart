import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_get_app_body.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slides.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rank_slide.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// The app-download page base URL a member's kiosk QR points at. The per-gym
/// download page (`/get-app/<gymId>`) is a separate workstream; the kiosk only
/// points at it. The canonical host/path is still being finalized, so this one
/// named constant is the single switch — never inline the URL at a call site.
const String kKioskAppDownloadBaseUrl = 'https://www.combatden.net/get-app';

/// Build the app-download URL the QR encodes for [gymId].
String kioskAppDownloadUrl(String gymId) => '$kKioskAppDownloadBaseUrl/$gymId';

/// The one solid popup surface the whole modal sits on. Named so a test can
/// assert the founder's structural rule — ONE popup, with the two cards and
/// the Done foot nested INSIDE it, nothing floating on the veil.
const Key kKioskGetAppPopup = Key('kiosk-get-app-popup');

/// The member-facing "Get the app" modal (founder feature UX-5) — the kiosk's
/// app-adoption funnel, opened by a tap on the retention glance or by the
/// home adopt strip's "Get it" button.
///
/// **It is ONE solid popup carrying two nested cards** (founder ruling): a
/// single lifted surface over the veil, holding the accent-soft app card
/// (white-labelled title, the book/earn/watch checks, the real scannable
/// download QR, the two sign-in steps) beside the auto-advancing "In the app"
/// showcase — with the countdown and Done INSIDE that surface, not dangling
/// under it. There is deliberately no spanning "Welcome to {gym}" header: the
/// gym is already named on the persistent kiosk header and on the app card's
/// own title, so a third naming only cost height on a screen that must not
/// scroll.
///
/// **Nothing here scrolls.** A member standing at a kiosk never discovers what
/// sits below a fold, so the whole composition fits the iPad landscape viewport
/// outright — see [KioskGetAppBody].
///
/// The veil absorbs taps so an accidental touch doesn't dismiss it: only Done
/// or the 60-second timer closes it. Done returns the member to whatever was
/// underneath (the glance, or the home); expiry means nobody is standing there
/// and returns home — both live in `KioskFlowCubit.closeAppModal`.
/// [secondsLeft] is the cubit's modal countdown; [gymId] scopes the QR.
///
/// Every showcase input is a catalogue the flow cubit fetched ONCE at kiosk
/// entry and cached — **this modal never fetches**, which is why it opens
/// instantly. See `kioskShowcaseSlides` for what each slide renders and why a
/// slide whose data is absent is omitted outright.
class KioskGetAppModal extends StatelessWidget {
  final String gymId;
  final int secondsLeft;

  /// The gym's real name, which white-labels the app card's title. Null /
  /// empty (no active gym name) falls back to naming the app generically
  /// rather than inventing a stand-in gym.
  final String? gymName;

  /// The checked-in member's sign-in address, when one is known (the glance
  /// path). Null from the idle home — step 2 then omits the address.
  final String? memberEmail;

  /// The gym's cached reward catalogue — the "Earn rewards" slide.
  final List<RewardResponse> rewards;

  /// Today's open classes already loaded by the flow — the "Book classes"
  /// slide. Empty from the idle home, which omits that slide.
  final List<EffectiveClassInstance> classes;

  /// The head of the gym's OWN curated video feed — the "Watch videos" slide.
  /// Empty for a gym with no feed (or a failed fetch), which omits the slide.
  final List<Video> videos;

  /// The gym's belt ladder — the "Track rank" slide. Carries no member link:
  /// that slide features a MIDDLE rung and an illustrative bar by design (see
  /// `KioskRankSlide`). Empty when the gym doesn't run ranks, which omits the
  /// slide and its dot.
  final List<KioskRankStep> rankLadder;

  const KioskGetAppModal({
    super.key,
    required this.gymId,
    required this.secondsLeft,
    this.gymName,
    this.memberEmail,
    this.rewards = const [],
    this.classes = const [],
    this.videos = const [],
    this.rankLadder = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        // Opaque so a tap on the veil is swallowed (never leaks to the glance
        // behind it); intentionally does nothing — Done / the 60s timer close.
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
                  // The popup takes the whole veiled area rather than
                  // shrink-wrapping: a bounded height is what lets the body
                  // lay the foot out first and give the cards the rest, which
                  // is how this composition guarantees it never scrolls.
                  child: SizedBox.expand(
                    child: _Popup(
                      child: KioskGetAppBody(
                        gymId: gymId,
                        gymName: gymName,
                        secondsLeft: secondsLeft,
                        memberEmail: memberEmail,
                        slides: kioskShowcaseSlides(
                          classes: classes,
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

/// The single solid surface the whole modal lives on — the same popup chrome
/// the kiosk's idle warning already uses (`popup` fill, the object-card radius,
/// a hairline border, the soft layered `cardShadow`), just at welcome-screen
/// width.
///
/// It is what makes the modal read as ONE thing that opened rather than two
/// panels floating on a veil, and it is the surface the two nested cards and
/// the Done foot all sit inside.
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
