import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/features/gym_setup/presentation/widgets/step_error_banner.dart';

/// Max length for the free-text street address — the backend's
/// `gyms.address` cap (mirrors the Settings gym-profile editor, which
/// keeps its own private const for the same column).
const int _kAddressMaxLength = 255;

/// Step 1 — enter the gym name, and optionally its street address.
///
/// The address is OPTIONAL on purpose: it adds zero required friction to
/// onboarding, and an owner who skips it can still set one later in
/// Settings → Gym profile. An empty field submits as null, never ''.
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
  final _addressController = TextEditingController();

  @override
  void dispose() {
    _gymNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _onSubmit() {
    if (_formKey.currentState?.validate() ?? false) {
      final address = _addressController.text.trim();
      context.read<GymSetupBloc>().add(
            GymSetupGymNameSubmitted(
              gymName: _gymNameController.text.trim(),
              address: address.isEmpty ? null : address,
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
                'What is your gym called, and where is it?',
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
          // Optional, so no validator — a blank box is a valid submit.
          // The optional marker rides the field's own `helperText` slot
          // (pSmall / text2nd), the shared widget's idiom for guidance
          // under a field. Two lines: a full street address usually
          // wraps (street + city/state/zip) but is never a paragraph.
          CustomTextField(
            controller: _addressController,
            label: 'Address',
            hintText: 'e.g. 1200 W 6th St, Austin, TX 78703',
            helperText:
                'Optional. You can add it later in Settings.',
            keyboardType: TextInputType.streetAddress,
            maxLines: 2,
            minLines: 1,
            enabled: !widget.isSubmitting,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_kAddressMaxLength),
            ],
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
