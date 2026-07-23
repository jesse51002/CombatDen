import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_card.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_showcase.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slides.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rank_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The app-download page base URL a member's kiosk QR points at. The per-gym
/// download page (`/get-app/<gymId>`) is a separate workstream; the kiosk only
/// points at it. The canonical host/path is still being finalized, so this one
/// named constant is the single switch — never inline the URL at a call site.
const String kKioskAppDownloadBaseUrl = 'https://www.combatden.net/get-app';

/// Build the app-download URL the QR encodes for [gymId].
String kioskAppDownloadUrl(String gymId) => '$kKioskAppDownloadBaseUrl/$gymId';

/// The member-facing "Get the CombatDen App" modal (founder feature UX-5) —
/// the approved kiosk WELCOME screen, shown as an overlay funnel opened from a
/// glance tap or the home QR panel.
///
/// It is the welcome screen's own composition: a spanning header naming the
/// gym, then the accent-soft app card on the left (title, benefit checks, the
/// real scannable download QR, the sign-in steps) beside the auto-advancing
/// "In the app" showcase on the right, over the shared timer + Done foot. It
/// is a big modal on purpose.
///
/// Two deliberate departures from the mockup's screen, both because the modal
/// can open with NO member known (from the idle home):
///  * the header names the GYM only (`Welcome to {gym}`). The mockup's
///    `Welcome to {gym}, {name}!` sits after a signup; a member name here
///    would sometimes be a guess, so it is never shown;
///  * step 2's address renders only when [memberEmail] is really known.
///
/// A veil over the current kiosk view (rendered like the idle warning). The
/// scrim absorbs taps so an accidental touch doesn't dismiss it — only Done or
/// the 60-second timer closes it, both returning to a fresh home.
/// [secondsLeft] is the cubit's modal countdown; [gymId] scopes the QR.
///
/// Every showcase input is a catalogue the flow cubit fetched ONCE at kiosk
/// entry and cached — **this modal never fetches**, which is why it opens
/// instantly. See `kioskShowcaseSlides` for what each slide renders and why a
/// slide whose data is absent is omitted outright.
class KioskGetAppModal extends StatelessWidget {
  final String gymId;
  final int secondsLeft;

  /// The gym's real name, for the spanning header. Null / empty (no active gym
  /// name) drops the "to {gym}" clause rather than inventing a stand-in.
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

  /// The gym's belt ladder, already tagged with the member's rung — the
  /// "Track rank" slide. Empty when the gym doesn't run ranks, which omits the
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
              padding: const EdgeInsets.all(DesignConstants.paddingBig),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: DesignConstants.dialogMaxWidthWide,
                  ),
                  // Scrolls on a short fold rather than clipping the QR.
                  child: SingleChildScrollView(
                    child: _WelcomeBody(
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
    );
  }
}

/// The welcome composition itself (mockup `.glance-top` + `.welcome-grid` +
/// `.glance-foot`): the spanning header over two equal-height panels, over the
/// auto-return foot.
class _WelcomeBody extends StatelessWidget {
  final String gymId;
  final String? gymName;
  final int secondsLeft;
  final String? memberEmail;
  final List<KioskShowcaseSlide> slides;

  const _WelcomeBody({
    required this.gymId,
    required this.gymName,
    required this.secondsLeft,
    required this.memberEmail,
    required this.slides,
  });

  @override
  Widget build(BuildContext context) {
    final card = KioskAppCard(
      downloadUrl: kioskAppDownloadUrl(gymId),
      memberEmail: memberEmail,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingBig,
      children: [
        _Header(gymName: gymName),
        if (slides.isEmpty)
          // A gym with nothing to show yet (no classes loaded, no rewards, no
          // feed, no ranks): the app card carries the screen alone rather than
          // an empty panel or a stand-in slide. Capped so it doesn't stretch
          // across the full welcome measure.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesignConstants.dialogMaxWidth,
              ),
              child: card,
            ),
          )
        else
          // Equal-height halves, like the glance's two panels: IntrinsicHeight
          // gives the unbounded scroll body a height for the stretch to resolve
          // against, so the showcase's slide stage gets a bounded box.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingLarge,
              children: [
                Expanded(child: card),
                Expanded(child: KioskAppShowcase(slides: slides)),
              ],
            ),
          ),
        _Foot(secondsLeft: secondsLeft),
      ],
    );
  }
}

/// The header spanning both panels (mockup `.glance-top`): one kiosk-scale
/// line that anchors the composition and says where the member is.
///
/// It states only what the kiosk certainly knows — the gym on the header and
/// in `selectedGym`. It never carries a member name: the modal also opens from
/// the idle home, where nobody has identified themselves.
class _Header extends StatelessWidget {
  final String? gymName;

  const _Header({required this.gymName});

  @override
  Widget build(BuildContext context) {
    final name = gymName?.trim() ?? '';
    return Text(
      name.isEmpty ? 'Welcome' : 'Welcome to $name',
      style: DesignConstants.kioskDisplay,
      textAlign: TextAlign.center,
      // A very long gym name wraps once, then clips — it must never push the
      // two panels off a short iPad fold.
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The modal's own footer: a hairline, the 60-second auto-close countdown, and
/// a Done button that returns to a fresh home.
class _Foot extends StatelessWidget {
  final int secondsLeft;

  const _Foot({required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        const Hairline(),
        Center(
          child: KioskReturnTimer(
            total: kKioskAppModalTimeout.inSeconds,
            secondsLeft: secondsLeft,
          ),
        ),
        Center(
          child: KioskOutlineButton(
            text: 'Done',
            onPressed: () => context.read<KioskFlowCubit>().closeAppModal(),
          ),
        ),
      ],
    );
  }
}
