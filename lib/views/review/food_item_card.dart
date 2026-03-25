import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/meal_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/food_item.dart';
import '../../services/haptic_service.dart';
import '../../widgets/labeled_text_field.dart';
import '../../widgets/sheet_handle.dart';

class FoodItemCard extends ConsumerStatefulWidget {
  final FoodItem item;
  final int index;

  const FoodItemCard({super.key, required this.item, required this.index});

  @override
  ConsumerState<FoodItemCard> createState() => _FoodItemCardState();
}

class _FoodItemCardState extends ConsumerState<FoodItemCard> {
  // Snapshot of the original AI estimate. The slider always multiplies
  // from this base, so repeated drags never compound the scaling.
  late final FoodItem _base;
  double _multiplier = 1.0;

  @override
  void initState() {
    super.initState();
    _base = widget.item;
  }

  int get _scaledCalories => (_base.calories * _multiplier).round();
  double get _scaledPortion => _base.portionSize * _multiplier;

  void _onSliderChanged(double value) {
    setState(() => _multiplier = value);
  }

  void _onSliderChangeEnd(double value) {
    HapticService.selection();
    ref.read(mealControllerProvider.notifier).updateItem(
          widget.index,
          _base.copyWith(
            portionSize: _base.portionSize * value,
            calories: (_base.calories * value).round(),
            protein:
                _base.protein != null ? _base.protein! * value : null,
            carbs: _base.carbs != null ? _base.carbs! * value : null,
            fat: _base.fat != null ? _base.fat! * value : null,
          ),
        );
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditItemSheet(item: widget.item, index: widget.index),
    );
  }

  Color _confidenceColor(double score) {
    if (score >= 0.8) return AppColors.success;
    if (score >= 0.5) return const Color(0xFFFFD166);
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    // Use a scaled copy of the base item to get the right portionLabel.
    final scaledItem = _base.copyWith(portionSize: _scaledPortion);
    final portionLabel = scaledItem.portionLabel;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Main row ──────────────────────────────────────────────
          Row(
            children: [
              // Confidence dot
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _confidenceColor(_base.confidenceScore),
                ),
              ),

              // Name + portion — tap to edit name / manual override
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticService.selection();
                    _showEditSheet(context);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.item.name, style: AppTextStyles.labelLarge),
                      const SizedBox(height: 3),
                      Text(portionLabel, style: AppTextStyles.caption),
                    ],
                  ),
                ),
              ),

              // Calorie pill — updates in real-time as slider moves
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_scaledCalories kcal',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Remove button
              GestureDetector(
                onTap: () {
                  HapticService.selection();
                  ref
                      .read(mealControllerProvider.notifier)
                      .removeItem(widget.index);
                },
                child: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
              ),
            ],
          ),

          // ── Portion slider ─────────────────────────────────────────
          // Visible directly on the card — swipe left/right to adjust
          // portion from 0.5× (half) to 3.0× (triple) in 0.5× steps.
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Text(
                  '0.5×',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: AppColors.accent,
                      inactiveTrackColor: AppColors.border,
                      thumbColor: AppColors.accent,
                      overlayColor:
                          AppColors.accent.withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: _multiplier,
                      min: 0.5,
                      max: 3.0,
                      divisions: 5,
                      onChanged: _onSliderChanged,
                      onChangeEnd: _onSliderChangeEnd,
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '${_multiplier == _multiplier.roundToDouble() ? _multiplier.toInt() : _multiplier.toStringAsFixed(1)}×',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Inline edit sheet (name + manual calorie override) ─────────────────────────

class _EditItemSheet extends ConsumerStatefulWidget {
  final FoodItem item;
  final int index;

  const _EditItemSheet({required this.item, required this.index});

  @override
  ConsumerState<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends ConsumerState<_EditItemSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _caloriesCtrl;
  late String _selectedUnit;

  static const _units = ['g', 'ml', 'piece', 'cup', 'slice', 'tbsp'];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item.name);
    _caloriesCtrl =
        TextEditingController(text: widget.item.calories.toString());
    _selectedUnit = widget.item.portionUnit;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _caloriesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final updated = widget.item.copyWith(
      name: _nameCtrl.text.trim().isEmpty
          ? widget.item.name
          : _nameCtrl.text.trim(),
      portionUnit: _selectedUnit,
      calories: int.tryParse(_caloriesCtrl.text) ?? widget.item.calories,
    );
    ref.read(mealControllerProvider.notifier).updateItem(widget.index, updated);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: 20),
            Text('Edit item', style: AppTextStyles.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Use the slider on the card to adjust portion size.',
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),

            // Name
            LabeledTextField(
              controller: _nameCtrl,
              label: 'Food name',
            ),
            const SizedBox(height: 12),

            // Calories override + unit
            Row(
              children: [
                Expanded(
                  child: LabeledTextField(
                    controller: _caloriesCtrl,
                    label: 'Calories (kcal)',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                _UnitPicker(
                  selected: _selectedUnit,
                  units: _units,
                  onChanged: (u) => setState(() => _selectedUnit = u),
                ),
              ],
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: () {
                HapticService.medium();
                _save();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitPicker extends StatelessWidget {
  final String selected;
  final List<String> units;
  final ValueChanged<String> onChanged;

  const _UnitPicker({
    required this.selected,
    required this.units,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Unit', style: AppTextStyles.caption),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected,
              dropdownColor: AppColors.card,
              style: AppTextStyles.bodyLarge,
              icon: const Icon(Icons.expand_more_rounded,
                  color: AppColors.textSecondary, size: 18),
              items: units
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (v) => v != null ? onChanged(v) : null,
            ),
          ),
        ),
      ],
    );
  }
}
