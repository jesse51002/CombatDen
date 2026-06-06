import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/gym_setup/data/models/employee_role.dart';
import 'package:crm/features/gym_setup/data/models/gym_with_role.dart';

/// Shown after sign-in when the user administers more than one gym.
///
/// Picking a gym makes it the active admin gym — its real UUID scopes
/// every CRM member view — and the auth gate then mounts the members
/// workspace. (A user with a single gym skips this and lands straight
/// in the workspace.)
class GymPickerScreen extends StatelessWidget {
  final List<GymWithRole> gyms;
  final void Function(GymWithRole gym) onSelected;

  const GymPickerScreen({
    super.key,
    required this.gyms,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingBig,
              children: [
                const _PickerHeader(),
                _GymList(gyms: gyms, onSelected: onSelected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerHeader extends StatelessWidget {
  const _PickerHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text('Choose a gym', style: DesignConstants.h1),
        Text(
          'You manage more than one gym. Pick one to open.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}

class _GymList extends StatelessWidget {
  final List<GymWithRole> gyms;
  final void Function(GymWithRole gym) onSelected;

  const _GymList({required this.gyms, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: DesignConstants.spacingMedium,
      children: [
        for (final gym in gyms)
          _GymCard(gym: gym, onTap: () => onSelected(gym)),
      ],
    );
  }
}

class _GymCard extends StatelessWidget {
  final GymWithRole gym;
  final VoidCallback onTap;

  const _GymCard({required this.gym, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DesignConstants.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        side: BorderSide(color: DesignConstants.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
          child: Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              Expanded(
                child: Text(
                  gym.gymName,
                  style: DesignConstants.h3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _RoleChip(role: gym.role),
              Icon(
                Icons.chevron_right,
                color: DesignConstants.text3rd,
                size: DesignConstants.iconSizeMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final EmployeeRole role;

  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundAlt,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Text(
        _label(role),
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text2nd,
        ),
      ),
    );
  }

  static String _label(EmployeeRole role) {
    switch (role) {
      case EmployeeRole.owner:
        return 'Owner';
      case EmployeeRole.admin:
        return 'Admin';
      case EmployeeRole.trainer:
        return 'Trainer';
      case EmployeeRole.unknown:
        return 'Staff';
    }
  }
}
