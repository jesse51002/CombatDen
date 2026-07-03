import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/models/waiver_type.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Picker dialog for the member-detail Waivers section's
/// "Sign new waiver" action: lists the gym's signable waivers
/// (custom + non-archived — any custom waiver is signable even
/// when the member's current memberships don't require it) and
/// returns the picked waiver id.
///
/// The caller opens [SignWaiverDialog] for the returned id so its
/// own `onSigned` refresh wiring runs — this dialog only picks.
class PickWaiverToSignDialog extends StatefulWidget {
  final String gymId;

  /// Waiver ids the member has already signed — rendered with a
  /// dim "Already signed" caption so staff don't re-sign blindly.
  final Set<String> signedWaiverIds;

  const PickWaiverToSignDialog({
    super.key,
    required this.gymId,
    this.signedWaiverIds = const {},
  });

  /// Shows the picker and resolves to the chosen waiver id, or
  /// null if the dialog was dismissed without a pick.
  static Future<String?> show({
    required BuildContext context,
    required String gymId,
    Set<String> signedWaiverIds = const {},
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => PickWaiverToSignDialog(
        gymId: gymId,
        signedWaiverIds: signedWaiverIds,
      ),
    );
  }

  @override
  State<PickWaiverToSignDialog> createState() =>
      _PickWaiverToSignDialogState();
}

class _PickWaiverToSignDialogState
    extends State<PickWaiverToSignDialog> {
  late Future<List<WaiverResponse>> _future;

  @override
  void initState() {
    super.initState();
    _future = MembershipsRepository(apiClient: ApiClient())
        .listWaivers(widget.gymId);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Sign a waiver',
      body: FutureBuilder<List<WaiverResponse>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(child: AppSpinner());
          }
          if (snapshot.hasError) {
            return ErrorMessage(
              message: snapshot.error.toString(),
            );
          }
          final waivers = [
            for (final w
                in snapshot.data ?? const <WaiverResponse>[])
              if (w.waiverType == WaiverType.custom &&
                  !w.isDeleted)
                w,
          ];
          if (waivers.isEmpty) {
            return Text(
              'No waivers to sign.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingSmall,
            children: [
              for (final w in waivers)
                _WaiverPickRow(
                  waiver: w,
                  alreadySigned:
                      widget.signedWaiverIds.contains(w.waiverId),
                  onTap: () =>
                      Navigator.of(context).pop(w.waiverId),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// One tappable waiver row in the picker.
class _WaiverPickRow extends StatelessWidget {
  final WaiverResponse waiver;
  final bool alreadySigned;
  final VoidCallback onTap;

  const _WaiverPickRow({
    required this.waiver,
    required this.alreadySigned,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(DesignConstants.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingMedium,
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(waiver.name, style: DesignConstants.p),
                  if (alreadySigned)
                    Text(
                      'Already signed',
                      style: DesignConstants.pSmall.copyWith(
                        color: DesignConstants.text2nd,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Symbols.chevron_right_sharp,
              size: DesignConstants.iconSizeSmall,
              color: DesignConstants.text2nd,
            ),
          ],
        ),
      ),
    );
  }
}
