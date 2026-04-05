import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../services/haptic_service.dart';
import '../../widgets/sheet_handle.dart';

// ─── Mood Rating Sheet ────────────────────────────────────────────────────────
//
// Shown after a meal is successfully saved. Lets the user optionally rate
// how they feel on two dimensions — Energy and Mood — on a 1–5 emoji scale.
//
// Ratings are persisted to meal_logs.feeling (JSONB) in Supabase. This seeds
// the Mood-Energy-Food Correlation Engine introduced in Phase 3, which after
// 14+ days of data surfaces insights like "high-carb lunches correlate with
// lower afternoon energy for you."
//
// The sheet is fully dismissible (swipe down or tap outside) — rating is
// optional and skipping must be zero-friction.

class MoodRatingSheet extends ConsumerStatefulWidget {
  final String mealLogId;

  const MoodRatingSheet({super.key, required this.mealLogId});

  @override
  ConsumerState<MoodRatingSheet> createState() => _MoodRatingSheetState();
}

class _MoodRatingSheetState extends ConsumerState<MoodRatingSheet> {
  int? _energy; // 1–5
  int? _mood;   // 1–5
  bool _saving = false;

  Future<void> _save() async {
    if (_energy == null && _mood == null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _saving = true);
    HapticService.medium();

    try {
      final feeling = <String, int>{
        if (_energy != null) 'energy': _energy!,
        if (_mood != null) 'mood': _mood!,
      };

      await Supabase.instance.client
          .from('meal_logs')
          .update({'feeling': feeling})
          .eq('id', widget.mealLogId);
    } catch (_) {
      // Non-fatal — rating failure must never surface to the user.
      // The meal has already been saved; this is optional metadata.
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;
    final hasRating = _energy != null || _mood != null;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 12, 24, botPad + 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          const SizedBox(height: 20),

          // Header
          Text('How do you feel?', style: AppTextStyles.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Optional — helps personalise your coaching insights over time.',
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),

          const SizedBox(height: 24),

          // Energy row
          _RatingRow(
            label: 'Energy',
            emoji: '⚡',
            value: _energy,
            onChanged: (v) {
              HapticService.selection();
              setState(() => _energy = v);
            },
          ),

          const SizedBox(height: 20),

          // Mood row
          _RatingRow(
            label: 'Mood',
            emoji: '😊',
            value: _mood,
            onChanged: (v) {
              HapticService.selection();
              setState(() => _mood = v);
            },
          ),

          const SizedBox(height: 28),

          // Action row
          Row(
            children: [
              // Skip
              Expanded(
                child: TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(
                    'Skip',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Save
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _saving || !hasRating ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.background,
                          ),
                        )
                      : const Text('Save rating'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Rating row ───────────────────────────────────────────────────────────────

class _RatingRow extends StatelessWidget {
  final String label;
  final String emoji;
  final int? value;
  final ValueChanged<int> onChanged;

  const _RatingRow({
    required this.label,
    required this.emoji,
    required this.value,
    required this.onChanged,
  });

  static const _labels = ['Very low', 'Low', 'Neutral', 'Good', 'Great'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$emoji  $label', style: AppTextStyles.labelLarge),
            const Spacer(),
            if (value != null)
              Text(
                _labels[value! - 1],
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(5, (i) {
            final score = i + 1;
            final isSelected = value == score;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(score),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.accentMuted : AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppColors.accent : AppColors.border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$score',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: isSelected
                            ? AppColors.accent
                            : AppColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
