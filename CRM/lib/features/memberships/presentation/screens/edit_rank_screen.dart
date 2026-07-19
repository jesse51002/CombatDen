import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/navigation/nav_pop.dart';
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
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/form/image_upload_picker_field.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Create or edit a main rank — a full-screen, repository-direct form
/// (mirrors the plan / waiver editors). Name, belt image,
/// classes-to-next-belt, sub-position count, and — behind a
/// "Custom sub-rank images" switch — a per-sub belt image.
///
/// The switch gates both the override pickers and the save payload: OFF
/// sends an empty overrides map (every sub-position falls back to the
/// main belt via the backend COALESCE), ON sends the entered overrides.
/// It defaults ON in edit mode when the rank already has overrides, OFF
/// otherwise. Entered values live in the overrides map independent of
/// the switch, so toggling OFF then ON restores them — only the payload
/// respects the switch.
///
/// Turning the switch OFF on a rank that had overrides saved is a
/// permanent, full JSONB wipe of every stored per-sub image (no merge,
/// unrecoverable), so [_save] confirms it first — see [_savedOverrideCount].
///
/// Within the map, overrides are **write-only**: shrinking the count
/// never prunes it, so a dormant sub image survives a count change and
/// revives if the count grows back. Uploads use the `rank` image
/// category (S3 `rank/` prefix); each override field also offers the
/// curated belt pool.
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

  /// Field-level error shown under the main belt picker on a failed submit
  /// (no belt image chosen). The main belt is required — an explicit pool
  /// pick or upload. Cleared the moment a belt is chosen. Edit mode starts
  /// satisfied by the rank's existing image.
  String? _mainImageError;
  int _subRankCount = 0;

  /// Write-only per-sub image map (`"0" -> url`). Seeded from the rank
  /// in edit mode; never has a key removed (persist-only).
  final Map<String, String> _overrides = {};

  /// Whether per-sub belt images are customized — the "Custom sub-rank
  /// images" switch. Gates the override pickers AND the save payload:
  /// OFF sends an empty overrides map (the effective belt image falls
  /// back to the main belt via the backend COALESCE), ON sends
  /// [_overrides]. Auto-ON in edit mode when the rank already has
  /// overrides, OFF otherwise (always OFF for create). Kept independent
  /// of [_overrides] so toggling OFF then ON restores the entered values
  /// — only the SAVE payload respects the switch.
  bool _customSubImages = false;

  /// How many per-sub belt overrides were PERSISTED on the rank at load
  /// time. Zero for create mode and for a rank that never had any. Drives
  /// the wipe-confirmation gate in [_save]: turning the switch OFF sends an
  /// empty overrides map, which permanently clears these saved images, so
  /// the save is confirmed first only when this is > 0 (i.e. the rank had
  /// saved overrides). A never-saved override added and removed this
  /// session leaves it at 0, so no confirm fires.
  int _savedOverrideCount = 0;

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
      // Remember how many overrides were saved, so [_save] can confirm the
      // permanent wipe if the switch is later turned off.
      _savedOverrideCount = r.subRankImageOverrides.length;
      // Auto-enable the custom-images section when the rank already has
      // per-sub overrides; a rank with none opens with the switch off.
      _customSubImages = _overrides.isNotEmpty;
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
    final formOk = _formKey.currentState?.validate() ?? false;
    // The main belt image is required — a save is blocked until an explicit
    // pool pick or upload (edit mode starts satisfied by the existing image).
    final imageOk = _mainImageUrl != null && _mainImageUrl!.isNotEmpty;
    setState(() => _mainImageError = imageOk ? null : 'Choose a belt image.');
    if (!formOk || !imageOk) return;
    // Turning the switch OFF on a rank that had saved sub-rank images sends
    // an empty overrides map, permanently wiping every stored per-sub image
    // (full JSONB replace, no merge, unrecoverable). Confirm before the wipe.
    if (_savedOverrideCount > 0 && !_customSubImages) {
      final confirmed = await ConfirmationModal.show(
        context: context,
        title: 'Delete custom sub-rank images?',
        message: 'The $_savedOverrideCount saved custom sub-rank image(s) '
            'for this rank will be permanently deleted, and every '
            'sub-position will fall back to the main belt image. '
            'This cannot be undone.',
        confirmLabel: 'Delete',
        confirmColor: DesignConstants.badRed,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final name = _nameController.text.trim();
      final classes = int.parse(_classesController.text.trim());
      // The switch gates the payload: ON sends the entered overrides,
      // OFF sends an explicit empty map so the backend clears any prior
      // overrides (the effective image falls back to the main belt via
      // COALESCE). The in-state _overrides map is untouched, so a toggle
      // back to ON restores what was entered.
      final overrides =
          _customSubImages ? _overrides : const <String, String>{};
      if (_isEdit) {
        await _repository.updateRank(
          widget.rank!.rankId,
          MainRankUpdateData(
            name: name,
            classesToNextMajor: classes,
            subRankCount: _subRankCount,
            imageUrl: _mainImageUrl,
            subRankImageOverrides: overrides,
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
          subRankImageOverrides: overrides,
        ));
      }
      if (!mounted) return;
      popOrGoTo(context, AppRoutes.membershipsRanks, result: true);
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
                      onPressed: () =>
                          popOrGoTo(context, AppRoutes.membershipsRanks),
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
                      onPressed: () =>
                          popOrGoTo(context, AppRoutes.membershipsRanks),
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
                      poolImages: AppConstants.rankBeltDefaultUrls,
                      isRequired: true,
                      // Belts are square art — preview 1:1 and contained so
                      // the image never crops or stretches (matches how
                      // RankBeltImage renders it on the ladder + detail).
                      aspectRatio: 1,
                      previewFit: BoxFit.contain,
                      imageUrl: _mainImageUrl,
                      errorText: _mainImageError,
                      onImageChosen: (url) => setState(() {
                        _mainImageUrl = url;
                        _mainImageError = null;
                      }),
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
                        _CustomSubImagesSwitch(
                          value: _customSubImages,
                          onChanged: (v) =>
                              setState(() => _customSubImages = v),
                        ),
                        if (_customSubImages) ...[
                          Text('Sub-rank belts',
                              style: DesignConstants.h2),
                          Text(
                            'Each position defaults to the main belt '
                            'image. Pick or upload a distinct image to '
                            'override it.',
                            style: DesignConstants.pSmall.copyWith(
                              color: DesignConstants.text2nd,
                            ),
                          ),
                          for (var i = 0; i < _subRankCount; i++)
                            ImageUploadPickerField(
                              key: ValueKey('sub-$i'),
                              label:
                                  subRankType.subLabel(i, showBase: true),
                              category: 'rank',
                              poolImages: AppConstants.rankBeltDefaultUrls,
                              aspectRatio: 1,
                              previewFit: BoxFit.contain,
                              imageUrl: _overrides[i.toString()],
                              defaultImageUrl: _mainImageUrl,
                              onImageChosen: (url) => setState(
                                () => _overrides[i.toString()] = url,
                              ),
                            ),
                        ],
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
                              onPressed: () => popOrGoTo(
                                context,
                                AppRoutes.membershipsRanks,
                              ),
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

/// Gates the per-sub-position belt override section. OFF (the default,
/// and edit mode with no existing overrides) uses the main belt image
/// for every sub-position; ON reveals a belt picker per sub-position.
/// Styled like the payment step's cash toggle.
class _CustomSubImagesSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CustomSubImagesSwitch({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: DesignConstants.primaryColor,
      contentPadding: EdgeInsets.zero,
      title: Text(
        'Custom sub-rank images',
        style: DesignConstants.p,
      ),
      subtitle: Text(
        'Off: every sub-position uses the main belt image.',
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text2nd,
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
