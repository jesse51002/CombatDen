import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/data/models/rank_create_request.dart';
import 'package:crm/features/memberships/data/models/rank_full_response.dart';
import 'package:crm/features/memberships/data/models/rank_update_data.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_color.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

/// Create or edit a rank. Three entry points:
/// - [showCreateGroup] — a brand-new main rank (its own group);
/// - [showAddToGroup] — a sub-rank within an existing main group;
/// - [showEdit] — edit a sub-rank's fields (name/classes/colour/image).
///
/// Position (main/sub order) is derived here, not typed — drag-to-
/// reorder on the ladder handles ordering after the fact.
class EditRankDialog extends StatefulWidget {
  final RanksBloc bloc;
  final String gymId;

  /// Edit mode: the rank being edited.
  final RankFullResponse? rank;

  /// New-group mode: the main order to assign the new group.
  final int? newGroupOrder;

  /// Add-to-group mode: the existing group to extend.
  final int? groupMainOrder;
  final String? groupMainName;
  final int? groupNextSubOrder;

  const EditRankDialog({
    super.key,
    required this.bloc,
    required this.gymId,
    this.rank,
    this.newGroupOrder,
    this.groupMainOrder,
    this.groupMainName,
    this.groupNextSubOrder,
  });

  static Future<void> showCreateGroup({
    required BuildContext context,
    required RanksBloc bloc,
    required String gymId,
    required List<RankFullResponse> existingRanks,
  }) {
    final nextOrder = existingRanks.isEmpty
        ? 0
        : existingRanks
                .map((r) => r.mainRankNumOrder)
                .reduce((a, b) => a > b ? a : b) +
            1;
    return showDialog<void>(
      context: context,
      builder: (_) => EditRankDialog(
        bloc: bloc,
        gymId: gymId,
        newGroupOrder: nextOrder,
      ),
    );
  }

  static Future<void> showAddToGroup({
    required BuildContext context,
    required RanksBloc bloc,
    required String gymId,
    required int mainOrder,
    required String mainName,
    required int nextSubOrder,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => EditRankDialog(
        bloc: bloc,
        gymId: gymId,
        groupMainOrder: mainOrder,
        groupMainName: mainName,
        groupNextSubOrder: nextSubOrder,
      ),
    );
  }

  static Future<void> showEdit({
    required BuildContext context,
    required RanksBloc bloc,
    required String gymId,
    required RankFullResponse rank,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => EditRankDialog(bloc: bloc, gymId: gymId, rank: rank),
    );
  }

  @override
  State<EditRankDialog> createState() => _EditRankDialogState();
}

class _EditRankDialogState extends State<EditRankDialog> {
  final _mainNameController = TextEditingController();
  final _subNameController = TextEditingController();
  final _classesController = TextEditingController(text: '20');
  final _colorController = TextEditingController();
  final _imageController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool get _isEdit => widget.rank != null;
  bool get _isNewGroup => !_isEdit && widget.newGroupOrder != null;

  @override
  void initState() {
    super.initState();
    final r = widget.rank;
    if (r != null) {
      _subNameController.text = r.subName;
      _classesController.text = r.classesTillRankup.toString();
      _colorController.text = r.color ?? '';
      _imageController.text = r.imageUrl ?? '';
    }
  }

  @override
  void dispose() {
    _mainNameController.dispose();
    _subNameController.dispose();
    _classesController.dispose();
    _colorController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  String? _validateRequired(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _validateClasses(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    return (n == null || n < 0) ? 'Enter a number (0 or more)' : null;
  }

  String? _validateColor(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return null;
    return parseRankColor(text) == null
        ? 'Use a #RRGGBB hex colour (e.g. #4A90D9)'
        : null;
  }

  String? get _color {
    final text = _colorController.text.trim();
    return text.isEmpty ? null : text;
  }

  String? get _image {
    final text = _imageController.text.trim();
    return text.isEmpty ? null : text;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final classes = int.parse(_classesController.text.trim());

    if (_isEdit) {
      widget.bloc.add(RankUpdated(
        rankId: widget.rank!.rankId,
        gymId: widget.gymId,
        data: RankUpdateData(
          subName: _subNameController.text.trim(),
          classesTillRankup: classes,
          color: _color,
          imageUrl: _image,
        ),
      ));
    } else {
      widget.bloc.add(RankCreated(RankCreateRequest(
        gymId: widget.gymId,
        mainRankNumOrder: _isNewGroup
            ? widget.newGroupOrder!
            : widget.groupMainOrder!,
        subRankNumOrder: _isNewGroup ? 0 : widget.groupNextSubOrder!,
        mainName: _isNewGroup
            ? _mainNameController.text.trim()
            : widget.groupMainName!,
        subName: _subNameController.text.trim(),
        classesTillRankup: classes,
        color: _color,
        imageUrl: _image,
      )));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isEdit ? 'Rank saved.' : 'Rank created.',
          style: DesignConstants.p.copyWith(color: DesignConstants.surface),
        ),
        backgroundColor: DesignConstants.goodGreen,
      ),
    );
    Navigator.of(context).pop();
  }

  String get _title {
    if (_isEdit) return 'Edit Rank';
    if (_isNewGroup) return 'New Main Rank';
    return 'Add Rank to ${widget.groupMainName}';
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: _title,
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingLarge,
          children: [
            if (_isNewGroup)
              CustomTextField(
                controller: _mainNameController,
                label: 'Main rank name',
                hintText: 'Blue',
                validator: _validateRequired,
              ),
            CustomTextField(
              controller: _subNameController,
              label: _isNewGroup ? 'Sub name' : 'Sub-rank name',
              hintText: 'Stripe II',
              validator: _validateRequired,
            ),
            CustomTextField(
              controller: _classesController,
              label: 'Classes required to advance',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: _validateClasses,
            ),
            _ColorField(
              controller: _colorController,
              validator: _validateColor,
            ),
            CustomTextField(
              controller: _imageController,
              label: 'Belt image URL (optional)',
              hintText: 'https://…',
              keyboardType: TextInputType.url,
            ),
          ],
        ),
      ),
      actions: AppDialogActions(
        primaryLabel: _isEdit ? 'Save' : 'Create',
        primaryOnPressed: _save,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// Hex colour field with a live swatch preview beside it.
class _ColorField extends StatelessWidget {
  final TextEditingController controller;
  final String? Function(String?) validator;

  const _ColorField({required this.controller, required this.validator});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: CustomTextField(
            controller: controller,
            label: 'Belt colour (optional)',
            hintText: '#4A90D9',
            validator: validator,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: DesignConstants.paddingBig),
          child: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => RankColorSwatch(
              color: controller.text.trim(),
              size: DesignConstants.iconSizeBig,
            ),
          ),
        ),
      ],
    );
  }
}
