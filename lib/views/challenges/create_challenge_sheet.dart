import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/challenge_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/challenge.dart';
import '../../services/haptic_service.dart';
import '../../widgets/labeled_text_field.dart';
import '../../widgets/sheet_handle.dart';

// ─── CreateChallengeSheet ─────────────────────────────────────────────────────
//
// Bottom sheet for creating a new Social Accountability Challenge.
// Fields:
//   - Title (required)
//   - Description (optional)
//   - Type picker (calorie budget | streak | macro target | custom)
//   - Target value (contextual label: "kcal budget" / "streak days" / etc.)
//   - Start / End date pickers
//   - Public toggle

class CreateChallengeSheet extends ConsumerStatefulWidget {
  const CreateChallengeSheet({super.key});

  @override
  ConsumerState<CreateChallengeSheet> createState() =>
      _CreateChallengeSheetState();
}

class _CreateChallengeSheetState
    extends ConsumerState<CreateChallengeSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _targetCtrl = TextEditingController(text: '1800');

  ChallengeType _type = ChallengeType.calorieBudget;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));
  bool _isPublic = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  String get _targetLabel => switch (_type) {
        ChallengeType.calorieBudget => 'Daily calorie budget (kcal)',
        ChallengeType.streak        => 'Streak target (days)',
        ChallengeType.macroTarget   => 'Daily protein target (g)',
        ChallengeType.custom        => 'Target value',
      };

  String get _targetHint => switch (_type) {
        ChallengeType.calorieBudget => 'e.g. 1800',
        ChallengeType.streak        => 'e.g. 7',
        ChallengeType.macroTarget   => 'e.g. 120',
        ChallengeType.custom        => 'e.g. 100',
      };

  Future<void> _pickDate({required bool isStart}) async {
    HapticService.selection();
    final initial = isStart ? _startDate : _endDate;
    final first = isStart ? DateTime.now() : _startDate;
    final last = DateTime.now().add(const Duration(days: 365));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.accent,
            surface: AppColors.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(picked)) {
          _endDate = picked.add(const Duration(days: 7));
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Please enter a challenge title.');
      HapticService.error();
      return;
    }

    final targetValue = double.tryParse(_targetCtrl.text.trim());
    if (targetValue == null || targetValue <= 0) {
      setState(() => _error = 'Please enter a valid target value.');
      HapticService.error();
      return;
    }

    await HapticService.heavy();
    setState(() { _saving = true; _error = null; });

    try {
      await ref.read(myChallengesProvider.notifier).create(
            title: title,
            description: _descCtrl.text.trim(),
            type: _type,
            targetValue: targetValue,
            startDate: _startDate,
            endDate: _endDate,
            isPublic: _isPublic,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not create challenge. Please try again.';
      });
      HapticService.error();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 20),
              Text('Create a challenge', style: AppTextStyles.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Challenge your friends to reach a nutrition goal together.',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              // Title
              LabeledTextField(
                controller: _titleCtrl,
                label: 'Challenge name',
                hint: 'e.g. 7-Day Clean Eating',
              ),
              const SizedBox(height: 12),

              // Description
              LabeledTextField(
                controller: _descCtrl,
                label: 'Description (optional)',
                hint: 'What\'s this challenge about?',
              ),
              const SizedBox(height: 20),

              // Type picker
              Text('Challenge type', style: AppTextStyles.caption),
              const SizedBox(height: 8),
              _TypePicker(
                selected: _type,
                onChanged: (t) {
                  HapticService.selection();
                  setState(() {
                    _type = t;
                    _targetCtrl.text = switch (t) {
                      ChallengeType.calorieBudget => '1800',
                      ChallengeType.streak        => '7',
                      ChallengeType.macroTarget   => '120',
                      ChallengeType.custom        => '100',
                    };
                  });
                },
              ),
              const SizedBox(height: 16),

              // Target value
              LabeledTextField(
                controller: _targetCtrl,
                label: _targetLabel,
                hint: _targetHint,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),

              // Date range
              Row(
                children: [
                  Expanded(
                    child: _DatePickerField(
                      label: 'Start date',
                      date: _startDate,
                      onTap: () => _pickDate(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DatePickerField(
                      label: 'End date',
                      date: _endDate,
                      onTap: () => _pickDate(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Public toggle
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Public challenge',
                            style: AppTextStyles.labelLarge),
                        Text(
                          _isPublic
                              ? 'Anyone can discover and join'
                              : 'Only people with the invite code can join',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isPublic,
                    activeThumbColor: AppColors.accent,
                    onChanged: (v) {
                      HapticService.selection();
                      setState(() => _isPublic = v);
                    },
                  ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.danger),
                ),
              ],

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create challenge'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Type picker ──────────────────────────────────────────────────────────────

class _TypePicker extends StatelessWidget {
  final ChallengeType selected;
  final ValueChanged<ChallengeType> onChanged;
  const _TypePicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ChallengeType.values.map((type) {
        final isSelected = type == selected;
        return GestureDetector(
          onTap: () => onChanged(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.accent : AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? AppColors.accent
                    : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(type.icon,
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  type.label,
                  style: AppTextStyles.caption.copyWith(
                    color: isSelected
                        ? AppColors.background
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Date picker field ────────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;
  const _DatePickerField(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '${date.day}/${date.month}/${date.year}',
                  style: AppTextStyles.labelLarge.copyWith(fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
