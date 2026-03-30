import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/primary_button.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';

/// Rank preset option with DB value and display label
class _RankPreset {
  final String value;
  final String label;

  const _RankPreset(this.value, this.label);
}

const _rankPresets = [
  _RankPreset('bjj', 'Brazilian Jiu-Jitsu'),
  _RankPreset('muay_thai', 'Muay Thai'),
  _RankPreset('karate', 'Karate'),
  _RankPreset('taekwondo', 'Taekwondo'),
  _RankPreset('judo', 'Judo'),
  _RankPreset('mma', 'MMA'),
];

/// Step 2: Configure rank settings for the gym
class RankConfigStep extends StatefulWidget {
  final String? errorMessage;
  final bool isSubmitting;

  const RankConfigStep({
    super.key,
    this.errorMessage,
    this.isSubmitting = false,
  });

  @override
  State<RankConfigStep> createState() =>
      _RankConfigStepState();
}

class _RankConfigStepState
    extends State<RankConfigStep> {
  bool _rankEnabled = true;
  String? _selectedPreset;

  void _onSubmit() {
    if (_rankEnabled && _selectedPreset == null) {
      return;
    }
    context.read<GymSetupBloc>().add(
          GymSetupRankConfigSubmitted(
            rankEnabled: _rankEnabled,
            rankPreset:
                _rankEnabled ? _selectedPreset : null,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rank System',
          style: DesignConstants.h1.copyWith(
            color: DesignConstants.text,
          ),
        ),
        SizedBox(
          height:
              DesignConstants.spacingSmall.toDouble(),
        ),
        Text(
          'Set up a ranking system for your members.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text
                .withValues(alpha: 0.7),
          ),
        ),
        SizedBox(
          height:
              DesignConstants.spacingBig.toDouble(),
        ),
        _buildRankToggle(),
        if (_rankEnabled) ...[
          SizedBox(
            height: DesignConstants.spacingLarge
                .toDouble(),
          ),
          _buildPresetSelector(),
        ],
        if (widget.errorMessage != null) ...[
          SizedBox(
            height: DesignConstants.spacingLarge
                .toDouble(),
          ),
          ErrorMessage(
            message: widget.errorMessage!,
          ),
        ],
        SizedBox(
          height:
              DesignConstants.spacingBig.toDouble(),
        ),
        PrimaryButton(
          text: 'Continue',
          isLoading: widget.isSubmitting,
          onPressed: widget.isSubmitting
              ? null
              : (_rankEnabled &&
                      _selectedPreset == null)
                  ? null
                  : _onSubmit,
        ),
      ],
    );
  }

  Widget _buildRankToggle() {
    return Row(
      mainAxisAlignment:
          MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Enable Ranks',
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text,
          ),
        ),
        Switch(
          value: _rankEnabled,
          onChanged: widget.isSubmitting
              ? null
              : (value) {
                  setState(() {
                    _rankEnabled = value;
                    if (!value) {
                      _selectedPreset = null;
                    }
                  });
                },
          activeThumbColor: DesignConstants.primary,
        ),
      ],
    );
  }

  Widget _buildPresetSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Discipline',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text
                .withValues(alpha: 0.7),
          ),
        ),
        SizedBox(
          height:
              DesignConstants.spacingMedium.toDouble(),
        ),
        Wrap(
          spacing:
              DesignConstants.spacingMedium.toDouble(),
          runSpacing:
              DesignConstants.spacingMedium.toDouble(),
          children: _rankPresets
              .map((preset) =>
                  _buildPresetChip(preset))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildPresetChip(_RankPreset preset) {
    final isSelected =
        _selectedPreset == preset.value;
    return GestureDetector(
      onTap: widget.isSubmitting
          ? null
          : () {
              setState(() {
                _selectedPreset = preset.value;
              });
            },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingLarge
              .toDouble(),
          vertical: DesignConstants.spacingMedium
              .toDouble(),
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? DesignConstants.primary
              : DesignConstants.cardBackground,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          border: Border.all(
            color: isSelected
                ? DesignConstants.primary
                : DesignConstants.buttonStroke,
            width: DesignConstants.buttonBorderSize,
          ),
        ),
        child: Text(
          preset.label,
          style: DesignConstants.p.copyWith(
            color: isSelected
                ? DesignConstants.background
                : DesignConstants.text,
          ),
        ),
      ),
    );
  }
}
