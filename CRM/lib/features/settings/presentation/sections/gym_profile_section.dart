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

/// The shared **Gym profile** editor — the gym's real name + its uploaded
/// brand logo. Saved through [SettingsBloc] via `PUT /api/v1/gyms/{gymId}`
/// (NOT optimistic): the field values come from [selectedGym] until the
/// backend commits, then [selectedGym] updates and a success SnackBar fires
/// off the state's monotonic `gymProfileSavedCount`.
///
/// One implementation, two hosts: the Settings screen and — admin context
/// only — the [GymProfileDialog] opened from the Theme tab's phone preview.
/// Both provide a [SettingsBloc] above this widget; the dialog host also owns
/// the error listener (the Settings screen already has one), so this section
/// only surfaces success.
///
/// [showHeader] hides the section's own title/subtitle when the host (the
/// dialog) already provides one. [onSaved] fires after a committed save, in
/// the same listener as the success SnackBar — the dialog host closes on it.
class GymProfileSection extends StatefulWidget {
  final bool showHeader;
  final VoidCallback? onSaved;

  const GymProfileSection({
    super.key,
    this.showHeader = true,
    this.onSaved,
  });

  @override
  State<GymProfileSection> createState() => _GymProfileSectionState();
}

class _GymProfileSectionState extends State<GymProfileSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;

  // The logo URL the section will persist. Seeded from the active gym; the
  // upload widget uploads on pick and hands back the CDN URL via
  // [onImageChosen].
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
        widget.onSaved?.call();
      },
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingLarge,
          children: [
            if (widget.showHeader) ...[
              Text('Gym profile', style: DesignConstants.h1),
              Text(
                'Your gym\'s name and logo. The logo shows in the CRM nav '
                'and on your members\' app.',
                style:
                    DesignConstants.p.copyWith(color: DesignConstants.text2nd),
              ),
            ],
            // Name above logo, always vertical. The plain Column keeps the
            // width constraint LOOSE, so the 480px cap genuinely applies —
            // the old side-by-side branch wrapped the field in Expanded,
            // whose TIGHT constraint overrode the cap and stretched the
            // field across the page.
            ConstrainedBox(
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
            ),
            ImageUploadPickerField(
              label: 'Gym logo',
              category: 'gym',
              imageUrl: _logoUrl,
              onImageChosen: (url) => setState(() => _logoUrl = url),
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
