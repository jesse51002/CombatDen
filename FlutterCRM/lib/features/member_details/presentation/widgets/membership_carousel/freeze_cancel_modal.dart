import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';

/// Modal with a segment selector for Freeze (account-level)
/// and Cancel (membership-level) actions.
class FreezeCancelModal extends StatefulWidget {
  final List<MembershipInfo> memberships;
  final String initialTab;

  const FreezeCancelModal({
    super.key,
    required this.memberships,
    this.initialTab = 'freeze',
  });

  /// Show the freeze/cancel modal dialog.
  static Future<void> show({
    required BuildContext context,
    required List<MembershipInfo> memberships,
    String initialTab = 'freeze',
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => FreezeCancelModal(
        memberships: memberships,
        initialTab: initialTab,
      ),
    );
  }

  @override
  State<FreezeCancelModal> createState() =>
      _FreezeCancelModalState();
}

class _FreezeCancelModalState
    extends State<FreezeCancelModal> {
  late String _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: DesignConstants.popup,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 480,
        ),
        child: Padding(
          padding: const EdgeInsets.all(
            DesignConstants.paddingSmall,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Segment selector
              _SegmentSelector(
                selected: _selectedTab,
                onChanged: (tab) =>
                    setState(() => _selectedTab = tab),
              ),
              const SizedBox(
                height: DesignConstants.spacingLarge,
              ),
              // Content
              if (_selectedTab == 'freeze')
                _FreezeContent()
              else
                _CancelContent(
                  memberships: widget.memberships,
                ),
              const SizedBox(
                height: DesignConstants.spacingLarge,
              ),
              // Action button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: Dispatch freeze/cancel event
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _selectedTab == 'freeze'
                            ? DesignConstants.okYellow
                            : DesignConstants.badRed,
                    foregroundColor:
                        DesignConstants.backgroundColor,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        DesignConstants.radiusBig,
                      ),
                    ),
                    padding:
                        const EdgeInsets.symmetric(
                      vertical:
                          DesignConstants.spacingMedium,
                    ),
                  ),
                  child: Text(
                    _selectedTab == 'freeze'
                        ? 'Freeze Account'
                        : 'Cancel Membership',
                    style: DesignConstants.h2.copyWith(
                      color:
                          DesignConstants.backgroundColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _SegmentSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusBig,
        ),
      ),
      child: Row(
        children: [
          _segment('freeze', 'Freeze'),
          _segment('cancel', 'Cancel'),
        ],
      ),
    );
  }

  Widget _segment(String value, String label) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: DesignConstants.spacingSmall,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? DesignConstants.primaryColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusBig,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: DesignConstants.h2.copyWith(
              color: isSelected
                  ? DesignConstants.text
                  : DesignConstants.text2nd,
              fontWeight: isSelected
                  ? FontWeight.w700
                  : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _FreezeContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Freeze Account',
          style: DesignConstants.h2,
        ),
        const SizedBox(
          height: DesignConstants.spacingSmall,
        ),
        Text(
          'Freezing will pause all memberships on this '
          'account. The member will not be billed during '
          'the freeze period.',
          style: DesignConstants.h2.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}

class _CancelContent extends StatelessWidget {
  final List<MembershipInfo> memberships;

  const _CancelContent({required this.memberships});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cancel Membership',
          style: DesignConstants.h2,
        ),
        const SizedBox(
          height: DesignConstants.spacingSmall,
        ),
        Text(
          'Cancelling a membership is permanent and '
          'cannot be undone. The member will lose access '
          'to all benefits of this plan.',
          style: DesignConstants.h2.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}
