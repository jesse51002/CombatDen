import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/rewards/bloc/rewards_bloc.dart';
import 'package:crm/features/rewards/bloc/rewards_event.dart';
import 'package:crm/features/rewards/bloc/rewards_state.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/image_upload_picker_field.dart';

enum _FormPhase { form, saving, success, error }

/// Create-or-edit dialog for a single gym reward.
///
/// Pass [existing] to enter edit mode (pre-fills fields). Omit for create.
/// Opens via [RewardFormDialog.show], which re-provides the [RewardsBloc]
/// so it is accessible inside the dialog's own route context.
class RewardFormDialog extends StatefulWidget {
  /// The reward being edited, or null for a new reward.
  final RewardResponse? existing;

  /// Pre-fill values from a template (create mode only).
  final String? prefillTitle;
  final int? prefillPointCost;
  final String? prefillPriceLabel;

  const RewardFormDialog({
    super.key,
    this.existing,
    this.prefillTitle,
    this.prefillPointCost,
    this.prefillPriceLabel,
  });

  static Future<void> show(
    BuildContext context, {
    RewardResponse? existing,
    String? prefillTitle,
    int? prefillPointCost,
    String? prefillPriceLabel,
  }) {
    final bloc = context.read<RewardsBloc>();
    return showDialog<void>(
      context: context,
      builder: (dialogCtx) => BlocProvider.value(
        value: bloc,
        child: RewardFormDialog(
          existing: existing,
          prefillTitle: prefillTitle,
          prefillPointCost: prefillPointCost,
          prefillPriceLabel: prefillPriceLabel,
        ),
      ),
    );
  }

  @override
  State<RewardFormDialog> createState() => _RewardFormDialogState();
}

class _RewardFormDialogState extends State<RewardFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _pointCostCtrl;
  late final TextEditingController _priceLabelCtrl;

  String? _imageUrl;
  _FormPhase _phase = _FormPhase.form;
  int? _tokenBefore;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(
      text: e?.title ?? widget.prefillTitle ?? '',
    );
    _pointCostCtrl = TextEditingController(
      text: e?.pointCost.toString() ??
          (widget.prefillPointCost?.toString() ?? ''),
    );
    _priceLabelCtrl = TextEditingController(
      text: e?.priceLabel ?? widget.prefillPriceLabel ?? '',
    );
    _imageUrl = e?.imageUrl;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _pointCostCtrl.dispose();
    _priceLabelCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    // The image never blocks: the backend fills a gift-box default when none
    // is uploaded, so an empty [_imageUrl] just omits image_url from the write.
    if (!_formKey.currentState!.validate()) return;
    final pointCost = int.tryParse(_pointCostCtrl.text.trim()) ?? 0;
    final priceLabel = _priceLabelCtrl.text.trim();
    _tokenBefore = context.read<RewardsBloc>().state.catalogSuccessToken;
    setState(() => _phase = _FormPhase.saving);

    if (_isEdit) {
      context.read<RewardsBloc>().add(RewardUpdateRequested(
        rewardId: widget.existing!.rewardId,
        title: _titleCtrl.text.trim(),
        pointCost: pointCost,
        priceLabel: priceLabel,
        imageUrl: _imageUrl,
      ));
    } else {
      context.read<RewardsBloc>().add(RewardCreateRequested(
        title: _titleCtrl.text.trim(),
        pointCost: pointCost,
        priceLabel: priceLabel,
        imageUrl: _imageUrl,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<RewardsBloc, RewardsState>(
      listenWhen: (prev, curr) =>
          _phase == _FormPhase.saving &&
          (curr.catalogSuccessToken != prev.catalogSuccessToken ||
              (curr.mutationError != null &&
                  curr.mutationError != prev.mutationError)),
      listener: (context, state) {
        if (state.catalogSuccessToken > (_tokenBefore ?? 0)) {
          setState(() => _phase = _FormPhase.success);
        } else if (state.mutationError != null) {
          setState(() => _phase = _FormPhase.error);
        }
      },
      child: AppDialog(
        title: _isEdit ? 'Edit Reward' : 'Add Reward',
        body: _body(context),
        showCloseButton: _phase != _FormPhase.saving,
      ),
    );
  }

  Widget _body(BuildContext context) {
    return switch (_phase) {
      _FormPhase.saving => const Padding(
        padding: EdgeInsets.symmetric(vertical: DesignConstants.paddingBig),
        child: Center(child: AppSpinner()),
      ),
      _FormPhase.success => _SuccessView(
        isEdit: _isEdit,
        onDone: () => Navigator.of(context).pop(),
      ),
      _FormPhase.error => _ErrorView(
        message: context.read<RewardsBloc>().state.mutationError ??
            'Something went wrong.',
        onRetry: () {
          context.read<RewardsBloc>().add(const RewardsErrorCleared());
          setState(() => _phase = _FormPhase.form);
        },
        onDismiss: () => Navigator.of(context).pop(),
      ),
      _FormPhase.form => _FormBody(
        formKey: _formKey,
        titleCtrl: _titleCtrl,
        pointCostCtrl: _pointCostCtrl,
        priceLabelCtrl: _priceLabelCtrl,
        imageUrl: _imageUrl,
        isEdit: _isEdit,
        onImageUploaded: (url) => setState(() => _imageUrl = url),
        onSubmit: _submit,
      ),
    };
  }
}

class _FormBody extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController titleCtrl;
  final TextEditingController pointCostCtrl;
  final TextEditingController priceLabelCtrl;
  final String? imageUrl;
  final bool isEdit;
  final void Function(String) onImageUploaded;
  final VoidCallback onSubmit;

  const _FormBody({
    required this.formKey,
    required this.titleCtrl,
    required this.pointCostCtrl,
    required this.priceLabelCtrl,
    required this.imageUrl,
    required this.isEdit,
    required this.onImageUploaded,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          ImageUploadPickerField(
            label: 'Reward Image',
            category: 'reward',
            imageUrl: imageUrl,
            defaultImageUrl: AppConstants.defaultRewardImageUrl,
            prominentUpload: true,
            onUploaded: onImageUploaded,
          ),
          CustomTextField(
            controller: titleCtrl,
            label: 'Title',
            hintText: 'e.g. Gym branded gear',
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Title is required.'
                : null,
          ),
          CustomTextField(
            controller: pointCostCtrl,
            label: 'Points Required',
            hintText: 'e.g. 1500',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n <= 0) {
                return 'Enter a positive number of points.';
              }
              return null;
            },
          ),
          CustomTextField(
            controller: priceLabelCtrl,
            label: 'Price Badge',
            hintText: 'e.g. Free or 30% off',
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'A price badge is required.'
                : null,
          ),
          AppPrimaryButton(
            text: isEdit ? 'Save Changes' : 'Add Reward',
            fullWidth: true,
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  final bool isEdit;
  final VoidCallback onDone;

  const _SuccessView({required this.isEdit, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignConstants.paddingBig),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          Icon(
            Symbols.check_circle_sharp,
            color: DesignConstants.goodGreen,
            size: DesignConstants.iconSizeBig,
            weight: DesignConstants.iconWeight,
          ),
          Text(
            isEdit ? 'Reward updated.' : 'Reward added to your store.',
            style: DesignConstants.h2,
            textAlign: TextAlign.center,
          ),
          AppPrimaryButton(text: 'Done', fullWidth: true, onPressed: onDone),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignConstants.paddingBig),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          Icon(
            Symbols.error_sharp,
            color: DesignConstants.badRed,
            size: DesignConstants.iconSizeBig,
            weight: DesignConstants.iconWeight,
          ),
          Text(message, style: DesignConstants.p, textAlign: TextAlign.center),
          Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              Expanded(
                child: AppPrimaryButton(
                  text: 'Retry',
                  fullWidth: true,
                  onPressed: onRetry,
                ),
              ),
              Expanded(
                child: AppPrimaryButton(
                  text: 'Dismiss',
                  fullWidth: true,
                  backgroundColor: DesignConstants.card,
                  textColor: DesignConstants.text,
                  onPressed: onDismiss,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
