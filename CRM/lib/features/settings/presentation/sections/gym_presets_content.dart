import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/presets/bloc/presets_bloc.dart';
import 'package:crm/features/presets/bloc/presets_event.dart';
import 'package:crm/features/presets/bloc/presets_state.dart';
import 'package:crm/features/presets/data/models/preset_models.dart';
import 'package:crm/features/settings/presentation/sections/gym_presets_template_card.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// The body of the gym-presets section: the template picker + import button.
///
/// Extracted from [GymPresetsSection] to keep each widget under 150 lines.
class GymPresetsContent extends StatelessWidget {
  const GymPresetsContent({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PresetsBloc, PresetsState>(
      builder: (ctx, state) {
        if (state.catalogStatus == PresetsCatalogStatus.loading ||
            state.catalogStatus == PresetsCatalogStatus.initial) {
          return const Center(child: AppSpinner());
        }

        if (state.catalogStatus == PresetsCatalogStatus.error) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingMedium,
            children: [
              ErrorMessage(
                message: state.error ?? 'Failed to load templates.',
              ),
              TextButton(
                onPressed: () => ctx
                    .read<PresetsBloc>()
                    .add(const PresetsTemplatesRequested()),
                child: const Text('Retry'),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingLarge,
          children: [
            _TemplatePicker(
              templates: state.templates,
              selectedId: state.selectedVideoGymId,
            ),
            if (state.selectedVideoGymId != null)
              _ImportAction(state: state),
          ],
        );
      },
    );
  }
}

class _TemplatePicker extends StatelessWidget {
  final List<TemplateCard> templates;
  final String? selectedId;

  const _TemplatePicker({required this.templates, required this.selectedId});

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) {
      return Text(
        'No templates available.',
        style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
      );
    }
    return Wrap(
      spacing: DesignConstants.spacingMedium,
      runSpacing: DesignConstants.spacingMedium,
      children: templates
          .map(
            (t) => GymPresetsTemplateCard(
              template: t,
              isSelected: t.videoGymId == selectedId,
              onTap: () => context
                  .read<PresetsBloc>()
                  .add(PresetsTemplateSelected(t.videoGymId)),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _ImportAction extends StatelessWidget {
  final PresetsState state;

  const _ImportAction({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.importStatus == PresetsImportStatus.success &&
        state.importResult != null) {
      return _SuccessRow(result: state.importResult!);
    }

    return AppPrimaryButton(
      text: 'Apply preset',
      isLoading: state.importStatus == PresetsImportStatus.importing,
      onPressed: state.importStatus == PresetsImportStatus.importing
          ? null
          : () => context
              .read<PresetsBloc>()
              .add(const PresetsImportRequested()),
    );
  }
}

class _SuccessRow extends StatelessWidget {
  final PresetImportResult result;

  const _SuccessRow({required this.result});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Imported: ${result.videosImported} videos · '
      '${result.classesImported} classes · '
      '${result.rewardsImported} rewards',
      style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
    );
  }
}
