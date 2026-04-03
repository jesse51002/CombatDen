import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';

/// Step 2: Enter owner first and last name (no API call)
class OwnerNameStep extends StatefulWidget {
  final String? errorMessage;
  final bool isSubmitting;

  const OwnerNameStep({
    super.key,
    this.errorMessage,
    this.isSubmitting = false,
  });

  @override
  State<OwnerNameStep> createState() =>
      _OwnerNameStepState();
}

class _OwnerNameStepState extends State<OwnerNameStep> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  void _onSubmit() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<GymSetupBloc>().add(
            GymSetupOwnerNameSubmitted(
              firstName:
                  _firstNameController.text.trim(),
              lastName:
                  _lastNameController.text.trim(),
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
            'Your Name',
            style: DesignConstants.h1.copyWith(
              color: DesignConstants.text,
            ),
          ),
          SizedBox(
            height: DesignConstants.spacingSmall
                ,
          ),
          Text(
            'Enter your name as the gym owner.',
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
            controller: _firstNameController,
            label: 'First Name',
            hintText: 'Enter your first name',
            enabled: !widget.isSubmitting,
            validator: (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return 'First name is required';
              }
              return null;
            },
          ),
          SizedBox(
            height: DesignConstants.spacingLarge
                ,
          ),
          CustomTextField(
            controller: _lastNameController,
            label: 'Last Name',
            hintText: 'Enter your last name',
            enabled: !widget.isSubmitting,
            validator: (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return 'Last name is required';
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
            text: 'Finish Setup',
            isLoading: widget.isSubmitting,
            onPressed:
                widget.isSubmitting ? null : _onSubmit,
          ),
        ],
      ),
    );
  }
}
