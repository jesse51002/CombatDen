import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/settings/bloc/settings_bloc.dart';
import 'package:crm/features/settings/bloc/settings_event.dart';
import 'package:crm/features/settings/bloc/settings_state.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/image_upload_picker_field.dart';

/// Max length the backend caps the gym name at.
const int _kNameMaxLength = 255;

/// Cap the name field so a single control doesn't stretch the whole page
/// (matches the timezone selector's cap).
const double _kNameFieldMaxWidth = 480;

/// Above this width the name field and the logo picker sit side by side; below
/// it they stack. Keeps the section compact where it hosts (the theme tab)
/// while staying readable on a narrow viewport.
const double _kSideBySideMinWidth = 700;

/// The shared **Gym profile** editor — the gym's real name + its uploaded
/// brand logo. Saved through [SettingsBloc] via `PUT /api/v1/gyms/{gymId}`
/// (NOT optimistic): the field values come from [selectedGym] until the
/// backend commits, then [selectedGym] updates and a success SnackBar fires
/// off the state's monotonic `gymProfileSavedCount`.
///
/// One implementation, two hosts: the Settings screen and — admin context
/// only — the member-app preview's Theme tab. Both provide a [SettingsBloc]
/// above this widget; the Theme-tab host also owns the error listener (the
/// Settings screen already has one), so this section only surfaces success.
class GymProfileSection extends StatefulWidget {
  const GymProfileSection({super.key});

  @override
  State<GymProfileSection> createState() => _GymProfileSectionState();
}

class _GymProfileSectionState extends State<GymProfileSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;

  // The logo URL the section will persist. Seeded from the active gym; the
  // upload widget uploads on pick and hands back the CDN URL via [onUploaded].
  String? _logoUrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: selectedGym.gymName ?? '');
    _logoUrl = selectedGym.logoUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    context.read<SettingsBloc>().add(
          GymProfileSaveRequested(
            gymName: _nameCtrl.text.trim(),
            logoUrl: _logoUrl,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsBloc, SettingsState>(
      listenWhen: (prev, curr) =>
          curr.gymProfileSavedCount > prev.gymProfileSavedCount,
      listener: (context, _) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Gym profile updated')),
          );
      },
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingLarge,
          children: [
            Text('Gym profile', style: DesignConstants.h1),
            Text(
              'Your gym\'s name and logo. The logo shows in the CRM nav and on '
              'your members\' app.',
              style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final nameField = ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _kNameFieldMaxWidth,
                  ),
                  child: CustomTextField(
                    controller: _nameCtrl,
                    label: 'Gym name',
                    hintText: 'e.g. Apex MMA',
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(_kNameMaxLength),
                    ],
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Gym name is required.'
                        : null,
                  ),
                );
                final logo = ImageUploadPickerField(
                  label: 'Gym logo',
                  category: 'gym',
                  imageUrl: _logoUrl,
                  onUploaded: (url) => setState(() => _logoUrl = url),
                );

                if (constraints.maxWidth >= _kSideBySideMinWidth) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: DesignConstants.spacingBig,
                    children: [
                      Expanded(child: nameField),
                      logo,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DesignConstants.spacingLarge,
                  children: [nameField, logo],
                );
              },
            ),
            BlocBuilder<SettingsBloc, SettingsState>(
              buildWhen: (prev, curr) =>
                  prev.savingGymProfile != curr.savingGymProfile,
              builder: (context, state) {
                return Row(
                  spacing: DesignConstants.spacingMedium,
                  children: [
                    AppPrimaryButton(
                      text: 'Save gym profile',
                      onPressed: state.savingGymProfile ? null : _save,
                    ),
                    if (state.savingGymProfile) const AppSpinner(),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
