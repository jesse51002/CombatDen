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

/// The "Name search" half of the kiosk home, as the two slots the home's band
/// layout places: the section head, and the live search field + result list
/// that floats in the flexible middle. No foot — the adopt strip spans the
/// whole screen below the columns, so both bodies share one flexible band.
KioskHomeHalf kioskNameSearchHalf() => const KioskHomeHalf(
      head: KioskSectionHead(
        title: 'Name search',
        subtitle: 'Search for your name for a quick check in',
      ),
      body: KioskNameSearch(),
    );

/// The name-search body: a live, debounced search over the gym roster feeding
/// a plain name list (no avatars/photos — a shared iPad shouldn't show member
/// faces). Selecting a name starts the check-in flow.
///
/// The results block carries its OWN top gap rather than a column spacing, so
/// an empty result list adds no height and can't nudge the field off the
/// centre it shares with the QR tile. The cap is [MeasuredMaxWidth], not a
/// plain `ConstrainedBox`: the home's bands resolve through `IntrinsicHeight`,
/// which would otherwise measure a wrapping result row at the FULL column
/// width and under-reserve its height.
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
                // The kiosk lifts muted WORDS off `text3rd` to the AA-passing
                // token — see the kiosk ramp in `design_constants.dart`.
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
