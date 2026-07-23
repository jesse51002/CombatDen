import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_search_results.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_section_head.dart';
import 'package:crm/shared/widgets/app_search_box.dart';

/// The "Name search" half of the kiosk home — a live, debounced search over
/// the gym roster feeding a plain name list (no avatars/photos: a shared iPad
/// shouldn't show member faces). Selecting a name starts the check-in flow.
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingBig,
        children: [
          const KioskSectionHead(
            title: 'Name search',
            subtitle: 'Search for your name for a quick check in',
          ),
          AppSearchBox(
            controller: _controller,
            hintText: 'Start typing your name',
            textStyle: DesignConstants.h2,
            onChanged: (value) =>
                context.read<KioskFlowCubit>().search(value),
          ),
          const KioskSearchResults(),
        ],
      ),
    );
  }
}
