import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/log_controller.dart';
import '../../controllers/meal_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'food_item_card.dart';

class ReviewSheet extends ConsumerStatefulWidget {
  const ReviewSheet({super.key});

  @override
  ConsumerState<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<ReviewSheet> {
  @override
  void initState() {
    super.initState();
    // Listen for the saved step and dismiss from the sheet's own context —
    // which is always valid while the modal route is alive, unlike the
    // button's context which may be inside AnimatedSwitcher's outgoing fade.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(mealControllerProvider, (previous, next) {
        if (next.step == MealProcessingStep.saved && mounted) {
          // Add the log optimistically before closing so the chip updates
          // instantly — no awaiting the DB round-trip.
          Navigator.of(context).pop();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final mealState = ref.watch(mealControllerProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.62, 0.95],
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // Body — animated between loading / review / error
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: mealState.isProcessing
                      ? _SkeletonLoader(
                          key: const ValueKey('skeleton'),
                          stepLabel: mealState.stepLabel,
                        )
                      : mealState.isReady
                          ? _ReviewContent(
                              key: const ValueKey('review'),
                              mealState: mealState,
                              scrollController: scrollController,
                            )
                          : mealState.error != null
                              ? _ErrorState(
                                  key: const ValueKey('error'),
                                  error: mealState.error!,
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey('empty'),
                                ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Review content ────────────────────────────────────────────────────────────

class _ReviewContent extends ConsumerWidget {
  final MealState mealState;
  final ScrollController scrollController;

  const _ReviewContent({
    super.key,
    required this.mealState,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = mealState.items;
    final isSaving = mealState.step == MealProcessingStep.saving;

    return Column(
      children: [
        // Scrollable list
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('What I ate', style: AppTextStyles.titleMedium),
                  _CaloriePill(calories: mealState.totalCalories),
                ],
              ),
              const SizedBox(height: 16),

              // Food items
              ...items.asMap().entries.map(
                    (e) => FoodItemCard(item: e.value, index: e.key),
                  ),

              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Nothing detected.\nTry better lighting.',
                      style: AppTextStyles.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

              const SizedBox(height: 8),
            ],
          ),
        ),

        // Save error message
        if (mealState.error != null && mealState.step == MealProcessingStep.review)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              mealState.error!.contains('relation')
                  ? 'Database not set up — run the SQL migration in Supabase.'
                  : mealState.error!,
              style: AppTextStyles.caption.copyWith(color: AppColors.danger),
              textAlign: TextAlign.center,
            ),
          ),

        // Confirm button — pinned
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            MediaQuery.of(context).padding.bottom + 20,
          ),
          child: _ConfirmButton(isSaving: isSaving),
        ),
      ],
    );
  }
}

class _ConfirmButton extends ConsumerWidget {
  final bool isSaving;
  const _ConfirmButton({required this.isSaving});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: isSaving
          ? null
          : () async {
              final log = await ref
                  .read(mealControllerProvider.notifier)
                  .confirmAndSave();

              // Optimistically update the daily chip immediately.
              // Dismissal is handled by ReviewSheet's listenManual so the
              // pop fires from a context that is always valid.
              if (log != null) {
                ref
                    .read(logControllerProvider.notifier)
                    .optimisticallyAddLog(log);
              }
            },
      child: isSaving
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.background,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Saving…',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.background,
                  ),
                ),
              ],
            )
          : const Text('Log this meal'),
    );
  }
}

class _CaloriePill extends StatelessWidget {
  final int calories;
  const _CaloriePill({required this.calories});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accentMuted,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$calories kcal',
        style: AppTextStyles.labelLarge.copyWith(
          color: AppColors.accent,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ─── Skeleton loader ───────────────────────────────────────────────────────────

class _SkeletonLoader extends StatefulWidget {
  final String stepLabel;
  const _SkeletonLoader({super.key, required this.stepLabel});

  @override
  State<_SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<_SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.2, end: 0.5)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _bone(double width, double height, {double radius = 8}) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.border.withValues(alpha: _anim.value),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step progress indicator
          _StepProgress(stepLabel: widget.stepLabel),
          const SizedBox(height: 24),

          // Skeleton rows mimicking food item cards
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _bone(120, 18),
              _bone(90, 28, radius: 20),
            ],
          ),
          const SizedBox(height: 18),
          _bone(double.infinity, 64, radius: 12),
          const SizedBox(height: 10),
          _bone(double.infinity, 64, radius: 12),
          const SizedBox(height: 10),
          _bone(260, 64, radius: 12),
          const Spacer(),
          _bone(double.infinity, 56, radius: 14),
        ],
      ),
    );
  }
}

// ─── Step progress widget ──────────────────────────────────────────────────────

class _StepProgress extends StatelessWidget {
  final String stepLabel;
  const _StepProgress({required this.stepLabel});

  @override
  Widget build(BuildContext context) {
    final isUploading = stepLabel.contains('Uploading');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _StepDot(active: isUploading, done: !isUploading),
            _StepLine(done: !isUploading),
            _StepDot(active: !isUploading, done: false),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            stepLabel,
            key: ValueKey(stepLabel),
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  const _StepDot({required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? AppColors.accent
            : active
                ? AppColors.accent
                : AppColors.border,
      ),
      child: done
          ? const Icon(Icons.check, size: 7, color: AppColors.background)
          : null,
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool done;
  const _StepLine({required this.done});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 40,
      height: 2,
      color: done ? AppColors.accent : AppColors.border,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ─── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends ConsumerWidget {
  final String error;
  const _ErrorState({super.key, required this.error});

  (String, String) _parse(String raw) {
    if (raw.contains('Upload failed') || raw.contains('Bucket') || raw.contains('bucket')) {
      return ('Storage not configured', raw);
    }
    if (raw.contains('Edge function unreachable') || raw.contains('deployed')) {
      return ('Edge function not deployed', raw);
    }
    if (raw.contains('HTTP 500') || raw.contains('OpenAI') || raw.contains('OPENAI')) {
      return ('OpenAI key missing or invalid', raw);
    }
    if (raw.contains('relation') || raw.contains('does not exist')) {
      return ('Database not set up', 'Run the SQL migration in Supabase SQL Editor.');
    }
    if (raw.contains('Session expired')) {
      return ('Session expired', 'Sign out and sign back in.');
    }
    return ('Analysis failed', raw);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (label, detail) = _parse(error);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline_rounded,
                color: AppColors.danger, size: 32),
          ),
          const SizedBox(height: 14),
          Text(label, style: AppTextStyles.titleMedium),
          const SizedBox(height: 12),

          // Scrollable debug box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxHeight: 100),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              child: Text(
                detail,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.danger,
                  height: 1.5,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: () {
              ref.read(mealControllerProvider.notifier).reset();
              Navigator.of(context).pop();
            },
            child: const Text('Try again'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              ref.read(mealControllerProvider.notifier).reset();
              Navigator.of(context).pop();
            },
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}
