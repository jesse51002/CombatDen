import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_bloc.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_state.dart';
import 'package:mobile_app/features/class_booking/data/class_detail_args.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_booking_footer.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_detail_topbar.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_image_banner.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_details_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_instructor_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_location_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_meta_section.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/repositories/member_signup_repository.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_event.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Class detail / booking screen for one occurrence.
///
/// In the app it reads the tapped occurrence + its booked state from the route
/// [ClassDetailArgs]; the capture harness injects [occurrence] directly (with
/// [captureController] / [imageKey] / [reserveKey], and no live blocs).
class ClassScreen extends StatelessWidget {
  const ClassScreen({
    super.key,
    this.occurrence,
    this.booked = false,
    this.captureController,
    this.imageKey,
    this.reserveKey,
  });

  /// Capture-only: the occurrence to render without a route. In the app it
  /// comes from the route [ClassDetailArgs] instead.
  final ClassOccurrence? occurrence;
  final bool booked;

  final ScrollController? captureController;
  final GlobalKey? imageKey;
  final GlobalKey? reserveKey;

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final occ = occurrence ??
        (args is ClassDetailArgs ? args.occurrence : null);
    final initialBooked = occurrence != null
        ? booked
        : (args is ClassDetailArgs ? args.booked : false);
    // The app path (no injected occurrence) has the live profile bloc and can
    // actually reserve; the capture path renders standalone.
    final live = occurrence == null;

    if (occ == null) return const _MissingClass();

    return BlocProvider<BookingBloc>(
      create: (_) => BookingBloc(
        repository: MemberSignupRepository(apiClient: ApiClient()),
        occurrence: occ,
        initiallyBooked: initialBooked,
      ),
      child: _ClassDetailView(
        occurrence: occ,
        live: live,
        captureController: captureController,
        imageKey: imageKey,
        reserveKey: reserveKey,
      ),
    );
  }
}

class _ClassDetailView extends StatelessWidget {
  const _ClassDetailView({
    required this.occurrence,
    required this.live,
    this.captureController,
    this.imageKey,
    this.reserveKey,
  });

  final ClassOccurrence occurrence;
  final bool live;
  final ScrollController? captureController;
  final GlobalKey? imageKey;
  final GlobalKey? reserveKey;

  void _onReserveSuccess(BuildContext context) {
    context
        .read<MemberProfileBloc>()
        .add(const MemberProfileRefreshRequested());
    Navigator.of(context).pushReplacementNamed(AppRoutes.reservingLoading);
  }

  void _onCancelSuccess(BuildContext context) {
    context
        .read<MemberProfileBloc>()
        .add(const MemberProfileRefreshRequested());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Reservation cancelled', style: DesignConstants.p),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: captureController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClassDetailTopbar(live: live),
                  KeyedSubtree(
                    key: imageKey,
                    child: ClassImageBanner(imageUrl: occurrence.imageUrl),
                  ),
                  _Body(occurrence: occurrence),
                ],
              ),
            ),
          ),
          ClassBookingFooter(buttonKey: reserveKey),
        ],
      ),
    );

    if (!live) return scaffold;
    return MultiBlocListener(
      listeners: [
        BlocListener<BookingBloc, BookingState>(
          listenWhen: (p, c) =>
              p.reserveSuccessToken != c.reserveSuccessToken,
          listener: (context, _) => _onReserveSuccess(context),
        ),
        BlocListener<BookingBloc, BookingState>(
          listenWhen: (p, c) => p.cancelSuccessToken != c.cancelSuccessToken,
          listener: (context, _) => _onCancelSuccess(context),
        ),
      ],
      child: scaffold,
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.occurrence});

  final ClassOccurrence occurrence;

  bool get _hasDescription =>
      occurrence.classDescription?.trim().isNotEmpty ?? false;

  bool get _hasInstructor =>
      (occurrence.resolvedInstructorBio?.trim().isNotEmpty ?? false) ||
      (occurrence.resolvedInstructorImageUrl?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        DesignConstants.screenHorizontalPadding,
        DesignConstants.spacingBig,
        DesignConstants.screenHorizontalPadding,
        DesignConstants.spacingBig,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingBig,
        children: [
          ClassMetaSection(
            occurrence: occurrence,
            gymName: selectedMember.gymName ?? '',
          ),
          if (_hasDescription) ...[
            const SectionDivider(),
            ClassDetailsSection(description: occurrence.classDescription),
          ],
          if (_hasInstructor) ...[
            const SectionDivider(),
            ClassInstructorSection(
              name: occurrence.resolvedInstructorName,
              bio: occurrence.resolvedInstructorBio,
              imageUrl: occurrence.resolvedInstructorImageUrl,
            ),
          ],
          const SectionDivider(),
          ClassLocationSection(gymName: selectedMember.gymName ?? ''),
        ],
      ),
    );
  }
}

/// Defensive fallback — the schedule always passes an occurrence, so this only
/// shows if the detail is opened with no arguments.
class _MissingClass extends StatelessWidget {
  const _MissingClass();

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      child: Center(
        child: Text(
          'Class not found.',
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
      ),
    );
  }
}
