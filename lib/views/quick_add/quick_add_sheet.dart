import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/log_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/food_item.dart';
import '../../widgets/labeled_text_field.dart';
import '../../widgets/sheet_handle.dart';

// ─── Manual Quick-Add Sheet ───────────────────────────────────────────────────
//
// Allows users to log a meal by name + calories without using the camera.
// Optional macro fields for users who know their nutritional breakdown.

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key});

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _nameCtrl = TextEditingController();
  final _calCtrl  = TextEditingController();
  final _protCtrl = TextEditingController();
  final _carbCtrl = TextEditingController();
  final _fatCtrl  = TextEditingController();

  bool _saving = false;
  bool _showMacros = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _calCtrl.dispose();
    _protCtrl.dispose();
    _carbCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final kcal = int.tryParse(_calCtrl.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'Enter a meal name');
      return;
    }
    if (kcal == null || kcal <= 0) {
      setState(() => _error = 'Enter a valid calorie amount');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    double? parseOpt(TextEditingController c) =>
        double.tryParse(c.text.trim());

    final item = FoodItem(
      name: name,
      portionSize: 1.0,
      portionUnit: 'serving',
      calories: kcal,
      protein: parseOpt(_protCtrl),
      carbs: parseOpt(_carbCtrl),
      fat: parseOpt(_fatCtrl),
      confidenceScore: 1.0,
    );

    final log = await directLogMeal(ref, items: [item]);

    if (!mounted) return;
    if (log != null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = 'Save failed — check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 16, 20, botPad + 20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 20),

            Text('Quick Add', style: AppTextStyles.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Log a meal without using the camera.',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),

            // Required fields
            LabeledTextField(
              controller: _nameCtrl,
              label: 'Meal name',
              hint: 'e.g. Chicken salad',
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            LabeledTextField(
              controller: _calCtrl,
              label: 'Calories',
              suffixText: 'kcal',
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _error = null),
            ),

            // Optional macros (collapsed by default)
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _showMacros = !_showMacros),
              child: Row(
                children: [
                  Text(
                    _showMacros ? 'Hide macros' : '+ Add macros (optional)',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _showMacros
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
                ],
              ),
            ),

            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: _showMacros
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: LabeledTextField(
                              controller: _protCtrl,
                              label: 'Protein',
                              suffixText: 'g',
                              keyboardType: const TextInputType
                                  .numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LabeledTextField(
                              controller: _carbCtrl,
                              label: 'Carbs',
                              suffixText: 'g',
                              keyboardType: const TextInputType
                                  .numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LabeledTextField(
                              controller: _fatCtrl,
                              label: 'Fat',
                              suffixText: 'g',
                              keyboardType: const TextInputType
                                  .numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // Validation error
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.danger),
              ),
            ],

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Log meal'),
            ),
          ],
        ),
      ),
    );
  }
}
