import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/features/gym_setup/presentation/widgets/step_error_banner.dart';

/// Step 1 — enter the gym name.
class GymNameStep extends StatefulWidget {
  final String? errorMessage;
  final bool isSubmitting;

  const GymNameStep({
    super.key,
    this.errorMessage,
    this.isSubmitting = false,
  });

  @override
  State<GymNameStep> createState() => _GymNameStepState();
}

class _GymNameStepState extends State<GymNameStep> {
  final _formKey = GlobalKey<FormState>();
  final _gymNameController = TextEditingController();

  @override
  void dispose() {
    _gymNameController.dispose();
    super.dispose();
  }

  void _onSubmit() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<GymSetupBloc>().add(
            GymSetupGymNameSubmitted(
              gymName: _gymNameController.text.trim(),
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                'Name Your Gym',
                style: DesignConstants.h1,
              ),
              Text(
                'What is your gym called?',
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
          CustomTextField(
            controller: _gymNameController,
            label: 'Gym Name',
            hintText: "Enter your gym's name",
            enabled: !widget.isSubmitting,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Gym name is required';
              }
              return null;
            },
          ),
          if (widget.errorMessage != null)
            StepErrorBanner(message: widget.errorMessage!),
          AppPrimaryButton(
            fullWidth: true,
            text: 'Continue',
            isLoading: widget.isSubmitting,
            onPressed:
                widget.isSubmitting ? null : _onSubmit,
          ),
        ],
      ),
    );
  }
}
