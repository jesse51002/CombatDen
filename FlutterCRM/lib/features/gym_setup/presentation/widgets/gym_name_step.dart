import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';

/// Step 1: Enter gym name
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
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Name Your Gym',
            style: DesignConstants.h1.copyWith(
              color: DesignConstants.text,
            ),
          ),
          SizedBox(
            height: DesignConstants.spacingSmall
                ,
          ),
          Text(
            'What is your gym called?',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text
                  .withValues(alpha: 0.7),
            ),
          ),
          SizedBox(
            height: DesignConstants.spacingBig
                ,
          ),
          CustomTextField(
            controller: _gymNameController,
            label: 'Gym Name',
            hintText: "Enter your gym's name",
            enabled: !widget.isSubmitting,
            validator: (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return 'Gym name is required';
              }
              return null;
            },
          ),
          if (widget.errorMessage != null) ...[
            SizedBox(
              height: DesignConstants.spacingLarge
                  ,
            ),
            ErrorMessage(
              message: widget.errorMessage!,
            ),
          ],
          SizedBox(
            height: DesignConstants.spacingBig
                ,
          ),
          AppPrimaryButton(fullWidth: true,
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

