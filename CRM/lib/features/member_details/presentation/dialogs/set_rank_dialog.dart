import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/memberships/data/models/rank_full_response.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_color.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Pick a member's rank explicitly — assign, correct, demote, or
/// unassign. Dispatches the change through [MemberDetailBloc].
class SetRankDialog extends StatefulWidget {
  final MemberDetailBloc bloc;
  final List<RankFullResponse> ladder;
  final String? currentRankId;

  const SetRankDialog({
    super.key,
    required this.bloc,
    required this.ladder,
    required this.currentRankId,
  });

  static Future<void> show({
    required BuildContext context,
    required MemberDetailBloc bloc,
    required List<RankFullResponse> ladder,
    required String? currentRankId,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => SetRankDialog(
        bloc: bloc,
        ladder: ladder,
        currentRankId: currentRankId,
      ),
    );
  }

  @override
  State<SetRankDialog> createState() => _SetRankDialogState();
}

class _SetRankDialogState extends State<SetRankDialog> {
  late String? _selected = widget.currentRankId;

  void _save() {
    if (_selected != widget.currentRankId) {
      widget.bloc.add(
        MemberRankChangeRequested(promote: false, rankId: _selected),
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Set Rank',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingTiny,
        children: [
          _Option(
            label: 'No rank (unassigned)',
            selected: _selected == null,
            onTap: () => setState(() => _selected = null),
          ),
          for (final rank in widget.ladder)
            _Option(
              label: rank.displayLabel,
              color: rank.color,
              selected: _selected == rank.rankId,
              onTap: () => setState(() => _selected = rank.rankId),
            ),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Save',
        primaryOnPressed: _save,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final String label;
  final String? color;
  final bool selected;
  final VoidCallback onTap;

  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.paddingSmall),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              selected
                  ? Symbols.check_circle_sharp
                  : Symbols.radio_button_unchecked_sharp,
              color: selected
                  ? DesignConstants.primaryColor
                  : DesignConstants.text3rd,
              size: DesignConstants.iconSizeMedium,
              weight: DesignConstants.iconWeight,
            ),
            if (color != null) RankColorSwatch(color: color),
            Expanded(child: Text(label, style: DesignConstants.p)),
          ],
        ),
      ),
    );
  }
}
