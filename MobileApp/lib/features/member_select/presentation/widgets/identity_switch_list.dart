import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';
import 'package:mobile_app/features/member_select/presentation/widgets/member_row.dart';
import 'package:mobile_app/shared/widgets/buttons/app_outline_button.dart';

// One skeleton block matches a MemberRow: 48 avatar + paddingSmall top/bottom.
const double _kSkeletonRowHeight = 80;
const int _kSkeletonRows = 3;

// Dim applied to the rows while a switch is in flight (a state value, like the
// animation opacities elsewhere — not a themable colour token).
const double _kBusyOpacity = 0.5;

/// The identity sheet's list area — the OTHER profiles this email resolves to.
///
/// Only this area has loading / error states: the sheet opens instantly from
/// the cached selection, and the header, the email and sign-out stay usable
/// while (or if) the re-fetch never lands. An offline sheet must still be able
/// to sign out, so a failure here never takes over the surface.
class IdentitySwitchList extends StatelessWidget {
  const IdentitySwitchList({
    super.key,
    required this.loading,
    required this.failed,
    required this.members,
    required this.busy,
    required this.onRetry,
    required this.onSelected,
  });

  final bool loading;
  final bool failed;
  final List<MemberIdentity> members;

  /// A switch is in flight — rows stop responding so a second tap can't race
  /// the first.
  final bool busy;

  final VoidCallback onRetry;
  final ValueChanged<MemberIdentity> onSelected;

  @override
  Widget build(BuildContext context) {
    if (loading) return const _Skeleton();
    if (failed) return _Error(onRetry: onRetry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        for (final member in members)
          Opacity(
            opacity: busy ? _kBusyOpacity : 1,
            child: MemberRow(
              member: member,
              onTap: busy ? () {} : () => onSelected(member),
            ),
          ),
      ],
    );
  }
}

/// Placeholder blocks, not a spinner: the list has a known shape, so holding
/// that shape keeps the sheet from jumping when the rows land.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          for (var i = 0; i < _kSkeletonRows; i++)
            Container(
              height: _kSkeletonRowHeight,
              decoration: BoxDecoration(
                color: DesignConstants.card,
                borderRadius: BorderRadius.circular(
                  DesignConstants.radiusSmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          "Can't load your other profiles.",
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        AppOutlineButton(
          text: 'Try again',
          borderRadius: DesignConstants.radiusSmall,
          borderColor: DesignConstants.text3rd,
          textColor: DesignConstants.text2nd,
          onPressed: onRetry,
        ),
      ],
    );
  }
}
