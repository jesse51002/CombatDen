import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/video_config/bloc/video_config_bloc.dart';
import 'package:crm/features/video_config/bloc/video_config_event.dart';
import 'package:crm/features/video_config/bloc/video_config_state.dart';
import 'package:crm/features/video_config/data/models/video_config_models.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Panel that surfaces when the agent has proposed a [VideoConfigDraft].
///
/// Shows the proposed disciplines, descriptions, and queries, with
/// **Confirm & Save** → [VideoConfigDraftConfirmed] and **Keep chatting** →
/// [VideoConfigDraftDismissed]. Includes a spinner while saving and an error
/// row on failure — never a silent dismiss (see CRM UX rule).
class VideoConfigDraftPanel extends StatelessWidget {
  final VideoConfigDraft draft;
  final VideoConfigSaveStatus saveStatus;
  final String? error;

  const VideoConfigDraftPanel({
    super.key,
    required this.draft,
    required this.saveStatus,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      backgroundColor: DesignConstants.primaryColor10,
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          _DraftHeader(draft: draft),
          const Hairline(),
          _QueriesPreview(queries: draft.queries),
          if (error != null)
            Text(
              error!,
              style: DesignConstants.p.copyWith(color: DesignConstants.badRed),
            ),
          _ActionRow(saveStatus: saveStatus),
        ],
      ),
    );
  }
}

class _DraftHeader extends StatelessWidget {
  final VideoConfigDraft draft;

  const _DraftHeader({required this.draft});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Row(
          spacing: DesignConstants.spacingSmall,
          children: [
            Icon(
              Symbols.auto_awesome_sharp,
              size: DesignConstants.iconSizeMedium,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.primaryColor,
            ),
            Text('Proposed config', style: DesignConstants.h3),
          ],
        ),
        if (draft.disciplines.isNotEmpty)
          Text(
            draft.disciplines.join(', '),
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        if (draft.videosDesc.isNotEmpty)
          Text(
            draft.videosDesc.length > 120
                ? '${draft.videosDesc.substring(0, 120)}…'
                : draft.videosDesc,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}

class _QueriesPreview extends StatelessWidget {
  final List<String> queries;

  const _QueriesPreview({required this.queries});

  @override
  Widget build(BuildContext context) {
    if (queries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          '${queries.length} search queries',
          style: DesignConstants.h3,
        ),
        for (final q in queries.take(3))
          Text(
            '• $q',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        if (queries.length > 3)
          Text(
            '+ ${queries.length - 3} more',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final VideoConfigSaveStatus saveStatus;

  const _ActionRow({required this.saveStatus});

  @override
  Widget build(BuildContext context) {
    final isSaving = saveStatus == VideoConfigSaveStatus.saving;
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        AppOutlineButton(
          text: 'Keep chatting',
          onPressed: isSaving
              ? null
              : () => context
                    .read<VideoConfigBloc>()
                    .add(const VideoConfigDraftDismissed()),
        ),
        AppPrimaryButton(
          text: 'Confirm & Save',
          isLoading: isSaving,
          onPressed: isSaving
              ? null
              : () => context
                    .read<VideoConfigBloc>()
                    .add(const VideoConfigDraftConfirmed()),
        ),
      ],
    );
  }
}
