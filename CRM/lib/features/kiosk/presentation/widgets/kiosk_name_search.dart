import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_home_columns.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_search_results.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_section_head.dart';
import 'package:crm/shared/widgets/app_search_box.dart';
import 'package:crm/shared/widgets/measured_max_width.dart';

/// The "Name search" half of the kiosk home, as the two slots the home's
/// band layout places: the section head, and the live search field + result
/// list that floats in the flexible middle.
/// Neither half has a footer: the app-adoption strip spans the whole screen
/// below the columns rather than closing one of them, so this half has no
/// weight to answer and both bodies share one flexible band.
KioskHomeHalf kioskNameSearchHalf() => const KioskHomeHalf(
      head: KioskSectionHead(
        title: 'Name search',
        subtitle: 'Search for your name for a quick check in',
      ),
      body: KioskNameSearch(),
    );

/// The name-search body: a live, debounced search over the gym roster feeding
/// a plain name list (no avatars/photos: a shared iPad shouldn't show member
/// faces). Selecting a name starts the check-in flow.
///
/// At rest the field is the whole body, so it sits on the band's exact centre
/// — the same centre the QR tile sits on. The results block below it carries
/// its OWN top gap instead of a column spacing, so an empty result list adds
/// no height and cannot nudge the field off that shared centre.
///
/// The field + results are capped at [DesignConstants.kioskHomeMeasure] and
/// centred, so the control reads as a deliberate object on the column's centre
/// line instead of a bar stretched to the edge of the screen. The cap is
/// [MeasuredMaxWidth], not a plain `ConstrainedBox`: the home's bands resolve
/// through `IntrinsicHeight`, which would otherwise measure a wrapping result
/// row at the FULL column width and under-reserve its height.
class KioskNameSearch extends StatefulWidget {
  const KioskNameSearch({super.key});

  @override
  State<KioskNameSearch> createState() => _KioskNameSearchState();
}

class _KioskNameSearchState extends State<KioskNameSearch> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<KioskFlowCubit, KioskFlowState>(
      // The idle guard resets the query to empty while still on home — clear
      // the field text with it so no half-typed name is left on screen.
      listenWhen: (prev, cur) =>
          prev.searchQuery.isNotEmpty && cur.searchQuery.isEmpty,
      listener: (_, _) => _controller.clear(),
      child: Center(
        child: MeasuredMaxWidth(
          maxWidth: DesignConstants.kioskHomeMeasure,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSearchBox(
                controller: _controller,
                hintText: 'Start typing your name',
                textStyle: DesignConstants.kioskFieldText,
                // The kiosk lifts muted WORDS off `text3rd` — see the contrast
                // note on the kiosk type ramp in `design_constants.dart`.
                hintColor: DesignConstants.text2nd,
                onChanged: (value) =>
                    context.read<KioskFlowCubit>().search(value),
              ),
              const KioskSearchResults(),
            ],
          ),
        ),
      ),
    );
  }
}
