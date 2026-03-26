import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/fasting_controller.dart';
import '../../controllers/log_controller.dart';
import '../../controllers/meal_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../services/haptic_service.dart';
import '../../widgets/sheet_handle.dart';
import '../paywall/paywall_sheet.dart';
import '../quick_add/quick_add_sheet.dart';
import '../review/review_sheet.dart';

// ─── Add Food Sheet ───────────────────────────────────────────────────────────
//
// Entry point for all food capture methods. Shown when the user taps the
// centre + FAB in the bottom navigation bar. Provides four paths into the
// meal logging pipeline without making any one path the default.

class AddFoodSheet extends ConsumerStatefulWidget {
  const AddFoodSheet({super.key});

  @override
  ConsumerState<AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends ConsumerState<AddFoodSheet> {
  bool _picking = false;

  bool _canLog() {
    final profile = ref.read(userProfileProvider).valueOrNull;
    return ref.read(logControllerProvider.notifier).canLog(profile);
  }

  void _showPaywall() {
    Navigator.of(context).pop(); // close this sheet first
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PaywallSheet(),
    );
  }

  // ── Fasting gate ─────────────────────────────────────────────────────────────
  //
  // When a fast is active, show a soft warning rather than a hard block.
  // Returns true when the user should proceed with logging, false to abort.
  // The user can log anyway (their choice) or end the fast first.

  Future<bool> _checkFastingGate() async {
    final activeFast =
        ref.read(fastingControllerProvider).valueOrNull;
    if (activeFast == null || !activeFast.isActive) return true;

    final protocol = activeFast.protocol.label;
    final remaining = activeFast.remaining;
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    final timeLeft =
        h > 0 ? '${h}h ${m}m left' : '${m}m left';

    HapticService.medium();

    final result = await showDialog<_FastingGateAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Text('🌙 ', style: TextStyle(fontSize: 20)),
            Text('You\'re fasting', style: AppTextStyles.titleMedium),
          ],
        ),
        content: Text(
          'Your $protocol fast has $timeLeft remaining. '
          'Eating now will break your fast.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_FastingGateAction.cancel),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_FastingGateAction.endFast),
            child: Text('End fast',
                style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_FastingGateAction.logAnyway),
            child: Text('Log anyway',
                style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (result == null || result == _FastingGateAction.cancel) return false;

    if (result == _FastingGateAction.endFast) {
      await ref.read(fastingControllerProvider.notifier).stop();
    }

    return true; // log anyway OR fast ended → allow logging
  }

  // ── Take a photo ────────────────────────────────────────────────────────────

  Future<void> _onTakePhoto() async {
    HapticService.selection();
    if (!_canLog()) {
      _showPaywall();
      return;
    }
    if (!await _checkFastingGate()) return;
    if (!mounted) return;
    Navigator.of(context).pop();
    context.push('/camera');
  }

  // ── Upload from gallery ─────────────────────────────────────────────────────

  Future<void> _onGalleryPick() async {
    HapticService.selection();
    if (!_canLog()) {
      _showPaywall();
      return;
    }
    if (!await _checkFastingGate()) return;
    if (!mounted) return;

    setState(() => _picking = true);

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 95,
    );

    if (!mounted) return;
    setState(() => _picking = false);

    if (picked == null) return;

    // Dismiss this sheet, then trigger AI pipeline + review sheet.
    Navigator.of(context).pop();

    // Brief post-frame delay ensures the sheet is fully dismissed on iOS
    // before the review sheet is pushed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HapticService.medium();
      ref.read(mealControllerProvider.notifier).analyseCapture(File(picked.path));
      _showReviewSheet();
    });
  }

  void _showReviewSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const ReviewSheet(),
    ).then((_) {
      final wasSaved =
          ref.read(mealControllerProvider).step == MealProcessingStep.saved;
      ref.read(mealControllerProvider.notifier).reset();
      if (wasSaved) {
        HapticService.medium();
      }
    });
  }

  // ── Scan barcode ────────────────────────────────────────────────────────────

  Future<void> _onScanBarcode() async {
    HapticService.selection();
    if (!_canLog()) {
      _showPaywall();
      return;
    }
    if (!await _checkFastingGate()) return;
    if (!mounted) return;
    Navigator.of(context).pop();
    context.push('/barcode');
  }

  // ── Quick add ───────────────────────────────────────────────────────────────

  Future<void> _onQuickAdd() async {
    HapticService.selection();
    if (!_canLog()) {
      _showPaywall();
      return;
    }
    if (!await _checkFastingGate()) return;
    if (!mounted) return;
    Navigator.of(context).pop();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QuickAddSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, botPad + 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: 20),
          Text('Add Food', style: AppTextStyles.titleMedium),
          const SizedBox(height: 4),
          Text(
            'How would you like to log your meal?',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),

          // ── Options ──────────────────────────────────────────────────────
          _Option(
            icon: Icons.camera_alt_rounded,
            iconColor: AppColors.accent,
            title: 'Take a Photo',
            subtitle: 'AI identifies your food instantly',
            onTap: _onTakePhoto,
          ),
          const SizedBox(height: 10),
          _Option(
            icon: Icons.photo_library_rounded,
            iconColor: const Color(0xFF64B5F6),
            title: 'Upload from Gallery',
            subtitle: 'Choose an existing photo',
            onTap: _picking ? null : _onGalleryPick,
            trailing: _picking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          _Option(
            icon: Icons.qr_code_scanner_rounded,
            iconColor: const Color(0xFFFFF176),
            title: 'Scan Barcode',
            subtitle: 'Log packaged foods from their label',
            onTap: _onScanBarcode,
          ),
          const SizedBox(height: 10),
          _Option(
            icon: Icons.edit_rounded,
            iconColor: const Color(0xFFA5D6A7),
            title: 'Quick Add',
            subtitle: 'Enter name and calories manually',
            onTap: _onQuickAdd,
          ),
        ],
      ),
    );
  }
}

// ─── Option tile ──────────────────────────────────────────────────────────────

class _Option extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _Option({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.labelLarge),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTextStyles.caption),
                  ],
                ),
              ),
              trailing ??
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Fasting gate action enum ──────────────────────────────────────────────────

enum _FastingGateAction { cancel, logAnyway, endFast }
