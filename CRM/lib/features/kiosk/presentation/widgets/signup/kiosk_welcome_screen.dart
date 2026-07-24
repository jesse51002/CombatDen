import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_name_format.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_card.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_showcase.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slides.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rank_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_get_app_modal.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The signup's terminal — they're a member, and the next thing they need is
/// the app.
///
/// **It COMPOSES the shipped `get_app/` set** rather than reinventing it: the
/// same app card (white-labelled title, benefit checks, the real scannable
/// download QR, the two sign-in steps) beside the same auto-advancing
/// showcase. The showcase's contents come from `KioskFlowState`'s four
/// gym-wide catalogues, warmed once at kiosk entry — so this screen fires
/// **zero** network calls and lands instantly on the frame after the charge.
///
/// **It greets the PAYER**, by first name, and it names the gym: a member
/// downloads *their gym's* app, and "CombatDen" means nothing to the person
/// standing at the iPad.
///
/// It does not scroll. The greeting and the foot are laid out first and the
/// two cards take a bounded share of what is left, so a short fold scales the
/// cards down (each carries its own `ShrinkToFit`) instead of hiding content a
/// standing member would never discover.
class KioskWelcomeScreen extends StatelessWidget {
  const KioskWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.welcomeCountdown != cur.welcomeCountdown ||
          prev.persons != cur.persons,
      builder: (context, state) {
        final payer = state.payer;
        return Padding(
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesignConstants.navMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DesignConstants.spacingLarge,
                children: [
                  _Greeting(firstName: kioskFirstName(payer.firstName)),
                  Expanded(child: _GetApp(memberEmail: payer.email)),
                  _Foot(secondsLeft: state.welcomeCountdown),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The green check disc and the one welcome line — the glance's confirmation
/// idiom, because this is the same beat: the thing worked, and here is what it
/// was.
class _Greeting extends StatelessWidget {
  final String firstName;

  const _Greeting({required this.firstName});

  String get _line {
    final gym = selectedGym.gymName?.trim() ?? '';
    if (gym.isEmpty) return 'Welcome, $firstName!';
    return 'Welcome to $gym, $firstName!';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Container(
          padding: const EdgeInsets.all(DesignConstants.spacingMedium),
          decoration: BoxDecoration(
            color: DesignConstants.goodGreen,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Symbols.check_sharp,
            size: DesignConstants.iconSizeLarge,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.onFill(DesignConstants.goodGreen),
          ),
        ),
        Flexible(
          child: Text(
            _line,
            style: DesignConstants.kioskDisplay,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// The app card beside the showcase, both read off the check-in lane's warmed
/// catalogues. A catalogue that came back empty simply drops its slide; with
/// no slides at all the app card carries the screen alone.
class _GetApp extends StatelessWidget {
  final String memberEmail;

  const _GetApp({required this.memberEmail});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskFlowCubit, KioskFlowState>(
      buildWhen: (prev, cur) =>
          prev.rewards != cur.rewards ||
          prev.showcaseClasses != cur.showcaseClasses ||
          prev.videos != cur.videos ||
          prev.rankLadder != cur.rankLadder,
      builder: (context, flow) {
        final gymId = selectedGym.gymId ?? '';
        final card = KioskAppCard(
          gymName: selectedGym.gymName,
          downloadUrl: kioskAppDownloadUrl(gymId),
          memberEmail: memberEmail,
        );
        final slides = kioskShowcaseSlides(
          classes: flow.showcaseClasses,
          rewards: flow.rewards,
          videos: flow.videos,
          rankLadder: kioskRankSteps(flow.rankLadder),
        );
        if (slides.isEmpty) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesignConstants.dialogMaxWidth,
              ),
              child: card,
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            Expanded(child: card),
            Expanded(child: KioskAppShowcase(slides: slides)),
          ],
        );
      },
    );
  }
}

/// The auto-return countdown and Done — both go home, and both release the
/// session's flow count through the cubit's one abandon path.
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
            total: kKioskSignupWelcomeHold.inSeconds,
            secondsLeft: secondsLeft,
          ),
        ),
        Center(
          child: KioskOutlineButton(
            text: 'Done',
            onPressed: () => context.read<KioskSignupCubit>().abandon(),
          ),
        ),
      ],
    );
  }
}
