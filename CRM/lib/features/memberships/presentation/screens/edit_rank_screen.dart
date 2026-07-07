import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/main_rank_create_request.dart';
import 'package:crm/features/memberships/data/models/main_rank_update_data.dart';
import 'package:crm/features/memberships/data/models/rank_ladder.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/form/image_upload_picker_field.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Create or edit a main rank — a full-screen, repository-direct form
/// (mirrors the plan / waiver editors). Name, belt image,
/// classes-to-next-belt, sub-position count, and a per-sub belt image
/// that defaults to the main belt.
///
/// Per-sub overrides are **write-only**: shrinking the count never
/// prunes the map, so a dormant sub image survives a count change and
/// revives if the count grows back. Uploads use the `rank` image
/// category (S3 `rank/` prefix).
class EditRankScreen extends StatefulWidget {
  /// The rank being edited, or null to create a new one.
  final MainRank? rank;

  const EditRankScreen({super.key, this.rank});

  @override
  State<EditRankScreen> createState() => _EditRankScreenState();
}

class _EditRankScreenState extends State<EditRankScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _classesController = TextEditingController(text: '20');
  final _repository = RanksRepository(apiClient: ApiClient());

  late final String _gymId = selectedGym.gymId ?? '';

  /// Loaded once — gives the gym's sub-rank type (for the per-sub
  /// labels) and, in create mode, the next ladder position.
  late Future<RankLadder> _ladderFuture;

  String? _mainImageUrl;
  int _subRankCount = 0;

  /// Write-only per-sub image map (`"0" -> url`). Seeded from the rank
  /// in edit mode; never has a key removed (persist-only).
  final Map<String, String> _overrides = {};

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.rank != null;

  @override
  void initState() {
    super.initState();
    final r = widget.rank;
    if (r != null) {
      _nameController.text = r.name;
      _classesController.text = r.classesToNextMajor.toString();
      _mainImageUrl = r.imageUrl;
      _subRankCount = r.subRankCount;
      _overrides.addAll(r.subRankImageOverrides);
    }
    _ladderFuture = _repository.listRanks(_gymId);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _classesController.dispose();
    super.dispose();
  }

  String? _validateRequired(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _validateClasses(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    return (n == null || n < 0) ? 'Enter a number (0 or more)' : null;
  }

  Future<void> _save(int nextOrder) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final name = _nameController.text.trim();
      final classes = int.parse(_classesController.text.trim());
      if (_isEdit) {
        await _repository.updateRank(
          widget.rank!.rankId,
          MainRankUpdateData(
            name: name,
            classesToNextMajor: classes,
            subRankCount: _subRankCount,
            imageUrl: _mainImageUrl,
            subRankImageOverrides: _overrides,
          ),
        );
      } else {
        await _repository.createRank(MainRankCreateRequest(
          gymId: _gymId,
          mainRankNumOrder: nextOrder,
          name: name,
          classesToNextMajor: classes,
          subRankCount: _subRankCount,
          imageUrl: _mainImageUrl,
          subRankImageOverrides: _overrides,
        ));
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      log('Failed to save rank', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the rank. Please try again.';
      });
    }
  }

  int _nextOrder(List<MainRank> ranks) {
    if (ranks.isEmpty) return 0;
    return ranks
            .map((r) => r.mainRankNumOrder)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeRoute: AppRoutes.memberships,
      child: FutureBuilder<RankLadder>(
        future: _ladderFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: AppSpinner());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(DesignConstants.paddingBig),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: DesignConstants.spacingLarge,
                  children: [
                    const ErrorMessage(
                      message: 'Could not load rank data. Try again.',
                    ),
                    AppOutlineButton(
                      text: 'Back',
                      borderRadius: DesignConstants.radiusSmall,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            );
          }
          final ladder = snapshot.data!;
          return _form(ladder.subRankType, _nextOrder(ladder.ranks));
        },
      ),
    );
  }

  Widget _form(RankSubType subRankType, int nextOrder) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingBig,
              children: [
                    _BackButton(
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Text(
                      _isEdit ? 'Edit rank' : 'New rank',
                      style: DesignConstants.h1,
                    ),
                    CustomTextField(
                      controller: _nameController,
                      label: 'Rank name',
                      hintText: 'Blue',
                      validator: _validateRequired,
                    ),
                    ImageUploadPickerField(
                      key: const ValueKey('main-belt'),
                      label: 'Belt image',
                      category: 'rank',
                      // Belts are square art — preview 1:1 and contained so
                      // the image never crops or stretches (matches how
                      // RankBeltImage renders it on the ladder + detail).
                      aspectRatio: 1,
                      previewFit: BoxFit.contain,
                      imageUrl: _mainImageUrl,
                      onUploaded: (url) =>
                          setState(() => _mainImageUrl = url),
                    ),
                    CustomTextField(
                      controller: _classesController,
                      label: 'Classes to next rank',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      validator: _validateClasses,
                    ),
                    // Sub-positions only exist when the gym uses a sub-rank
                    // style; a 'none' gym has no stripes/divisions, so hide
                    // the whole section. The rank's stored sub_rank_count is
                    // left as-is (persist-only) — hiding never zeroes it.
                    if (subRankType != RankSubType.none) ...[
                      _SubCountStepper(
                        count: _subRankCount,
                        onChanged: (v) => setState(() => _subRankCount = v),
                      ),
                      if (_subRankCount > 0) ...[
                        const Hairline(),
                        Text('Sub-rank belts', style: DesignConstants.h2),
                        Text(
                          'Each position defaults to the main belt image. '
                          'Upload a distinct image to override it.',
                          style: DesignConstants.pSmall.copyWith(
                            color: DesignConstants.text2nd,
                          ),
                        ),
                        for (var i = 0; i < _subRankCount; i++)
                          ImageUploadPickerField(
                            key: ValueKey('sub-$i'),
                            label: subRankType.subLabel(i, showBase: true),
                            category: 'rank',
                            aspectRatio: 1,
                            previewFit: BoxFit.contain,
                            imageUrl: _overrides[i.toString()],
                            defaultImageUrl: _mainImageUrl,
                            onUploaded: (url) => setState(
                              () => _overrides[i.toString()] = url,
                            ),
                          ),
                      ],
                    ],
                    if (_error != null) ErrorMessage(message: _error!),
                    Row(
                      children: [
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: DesignConstants.spacingMedium,
                          children: [
                            AppOutlineButton(
                              text: 'Cancel',
                              borderRadius: DesignConstants.radiusSmall,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            AppPrimaryButton(
                              text: _isEdit ? 'Save' : 'Create',
                              borderRadius: DesignConstants.radiusSmall,
                              isLoading: _saving,
                              onPressed:
                                  _saving ? null : () => _save(nextOrder),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
  }

}

/// A +/- stepper for the sub-position count (min 0). Shrinking never
/// prunes stored per-sub images — the parent keeps them (persist-only).
class _SubCountStepper extends StatelessWidget {
  final int count;
  final ValueChanged<int> onChanged;

  const _SubCountStepper({required this.count, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text('Sub-positions', style: DesignConstants.h2),
        Text(
          'Stripes or divisions within this belt. Zero means the belt '
          'is itself the rank.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        Row(
          spacing: DesignConstants.spacingLarge,
          children: [
            _StepButton(
              icon: Symbols.remove_sharp,
              onPressed: count > 0 ? () => onChanged(count - 1) : null,
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: DesignConstants.h1,
              ),
            ),
            _StepButton(
              icon: Symbols.add_sharp,
              onPressed: () => onChanged(count + 1),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _StepButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(DesignConstants.radiusSmall),
              border: Border.all(
                color: DesignConstants.text,
                width: DesignConstants.buttonBorder,
              ),
            ),
            child: Icon(
              icon,
              size: DesignConstants.iconSizeMedium,
              color: DesignConstants.text,
              weight: DesignConstants.iconWeight,
            ),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.all(DesignConstants.spacingSmall),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Icon(
                Symbols.arrow_back_sharp,
                size: DesignConstants.iconSizeMedium,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.text,
              ),
              Text('Ranks', style: DesignConstants.h3),
            ],
          ),
        ),
      ),
    );
  }
}
