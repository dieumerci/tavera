import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/camera_controller.dart';
import '../../controllers/log_controller.dart';
import '../../controllers/meal_controller.dart';
import '../../models/user_profile.dart';
import '../../widgets/sheet_handle.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../widgets/tavera_loading.dart';
import '../paywall/paywall_sheet.dart';
import '../review/review_sheet.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  bool _flashOn = false;

  // White flash on capture — immediate tactile feedback
  late final AnimationController _flashCtrl;
  late final Animation<double> _flashAnim;

  // Pulse ring on capture button while idle
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Chip celebration pop after a meal is successfully saved
  late final AnimationController _chipFlashCtrl;
  late final Animation<double> _chipFlashAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _flashAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _chipFlashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    // Bounces up to 1.18× then settles back to 1.0
    _chipFlashAnim = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.18)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 1.18, end: 1.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 60),
    ]).animate(_chipFlashCtrl);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashCtrl.dispose();
    _pulseCtrl.dispose();
    _chipFlashCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    super.didChangeAppLifecycleState(lifecycle);
    if (lifecycle == AppLifecycleState.resumed) {
      ref.read(cameraControllerProvider.notifier).reinitialise();
    }
  }

  Future<void> _onCapture() async {
    final profile = ref.read(userProfileProvider).valueOrNull;
    final logCtrl = ref.read(logControllerProvider.notifier);

    if (!logCtrl.canLog(profile)) {
      _showPaywall();
      return;
    }

    HapticFeedback.mediumImpact();

    // Trigger white flash immediately — tactile feedback before anything async
    _flashCtrl.forward(from: 0).then((_) => _flashCtrl.reverse());

    final file = await ref.read(cameraControllerProvider.notifier).capture();
    if (file == null || !mounted) return;

    // Kick off AI pipeline — sheet opens instantly with skeleton
    ref.read(mealControllerProvider.notifier).analyseCapture(file);
    if (!mounted) return;
    _showReviewSheet();
  }

  Future<void> _onGalleryPick() async {
    final profile = ref.read(userProfileProvider).valueOrNull;
    final logCtrl = ref.read(logControllerProvider.notifier);

    if (!logCtrl.canLog(profile)) {
      _showPaywall();
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 95, // light pre-compression; meal_controller compresses further
    );

    if (picked == null || !mounted) return;

    HapticFeedback.mediumImpact();
    ref
        .read(mealControllerProvider.notifier)
        .analyseCapture(File(picked.path));
    _showReviewSheet();
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
      // Check BEFORE reset — if saved, celebrate with chip bounce.
      final wasSaved =
          ref.read(mealControllerProvider).step == MealProcessingStep.saved;
      ref.read(mealControllerProvider.notifier).reset();
      if (wasSaved) _chipFlashCtrl.forward(from: 0);
    });
  }

  void _showPaywall() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PaywallSheet(),
    );
  }

  void _toggleFlash() {
    final ctrl = ref.read(cameraControllerProvider).valueOrNull?.controller;
    if (ctrl == null) return;
    setState(() => _flashOn = !_flashOn);
    ctrl.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
  }

  @override
  Widget build(BuildContext context) {
    final cameraAsync = ref.watch(cameraControllerProvider);
    final logState = ref.watch(logControllerProvider);
    final mealState = ref.watch(mealControllerProvider);
    final profile = ref.watch(userProfileProvider).valueOrNull;

    final isCapturing = cameraAsync.valueOrNull?.isCapturing ?? false;
    final isProcessing = mealState.isProcessing;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ──────────────────────────────────────────
          cameraAsync.when(
            data: (cam) {
              if (cam.needsExplanation) {
                return const _CameraRationaleScreen();
              }
              if (cam.isPermissionDenied) {
                return const _CameraPermissionScreen();
              }
              return cam.isReady
                  ? _CameraPreviewFill(controller: cam.controller!)
                  : _CameraPlaceholder(message: cam.error ?? 'Camera unavailable');
            },
            loading: () => const _CameraPlaceholder(message: null),
            error: (e, _) => _CameraPlaceholder(message: e.toString()),
          ),

          // ── Viewfinder plate guide ───────────────────────────────────
          // Subtle circle hints where to frame the meal. Hidden during
          // processing so it doesn't compete with the overlay spinner.
          if (!isProcessing)
            Positioned.fill(
              child: CustomPaint(painter: _PlateGuidePainter()),
            ),

          // ── Capture flash overlay ────────────────────────────────────
          AnimatedBuilder(
            animation: _flashAnim,
            builder: (_, __) => _flashAnim.value > 0
                ? Opacity(
                    opacity: _flashAnim.value * 0.7,
                    child: const ColoredBox(
                      color: Colors.white,
                      child: SizedBox.expand(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // ── Processing overlay (while AI runs) ───────────────────────
          if (isProcessing) _ProcessingOverlay(stepLabel: mealState.stepLabel),

          // ── Top controls ─────────────────────────────────────────────
          if (!isProcessing)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _GlassButton(
                      icon: Icons.person_outline_rounded,
                      onTap: () => context.push('/profile'),
                    ),
                    ScaleTransition(
                      scale: _chipFlashAnim,
                      child: _DailyChip(logState: logState, profile: profile),
                    ),
                    _GlassButton(
                      icon: _flashOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      onTap: _toggleFlash,
                    ),
                  ],
                ),
              ),
            ),

          // ── History grid button ──────────────────────────────────────
          if (!isProcessing)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              right: 20,
              child: _GlassButton(
                icon: Icons.grid_view_rounded,
                onTap: () => context.push('/history'),
              ),
            ),

          // ── Bottom bar: gallery  |  capture  |  (spacer) ────────────
          if (!isProcessing)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 32,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Gallery fallback
                  _GlassButton(
                    icon: Icons.photo_library_outlined,
                    onTap: _onGalleryPick,
                  ),
                  const SizedBox(width: 36),
                  // Primary shutter
                  _CaptureButton(
                    onTap: _onCapture,
                    isCapturing: isCapturing,
                    pulseAnim: _pulseAnim,
                  ),
                  // Water quick-add — mirrors gallery button, keeps shutter centred
                  _WaterButton(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Processing overlay ────────────────────────────────────────────────────────

class _ProcessingOverlay extends StatelessWidget {
  final String stepLabel;
  const _ProcessingOverlay({required this.stepLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TaveraLoading(size: 36),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                stepLabel,
                key: ValueKey(stepLabel),
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Camera preview ────────────────────────────────────────────────────────────

class _CameraPreviewFill extends StatelessWidget {
  final CameraController controller;
  const _CameraPreviewFill({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.height ?? 1,
          height: controller.value.previewSize?.width ?? 1,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  final String? message;
  const _CameraPlaceholder({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: message == null
            ? const TaveraLoading()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.camera_alt_outlined,
                      color: AppColors.textSecondary, size: 40),
                  const SizedBox(height: 12),
                  Text(message!, style: AppTextStyles.bodyMedium),
                ],
              ),
      ),
    );
  }
}

// ─── Viewfinder guide ──────────────────────────────────────────────────────────

class _PlateGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Centre the circle in the upper 60 % of the screen — below the top
    // controls and above the shutter button.
    final cx = size.width / 2;
    final cy = size.height * 0.42;
    final radius = size.width * 0.38;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Outer ring
    canvas.drawCircle(Offset(cx, cy), radius, paint);

    // Four small corner ticks at N / E / S / W for a crosshair feel
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const tickLen = 14.0;
    // North
    canvas.drawLine(
        Offset(cx, cy - radius + 2), Offset(cx, cy - radius + tickLen), tickPaint);
    // South
    canvas.drawLine(
        Offset(cx, cy + radius - 2), Offset(cx, cy + radius - tickLen), tickPaint);
    // West
    canvas.drawLine(
        Offset(cx - radius + 2, cy), Offset(cx - radius + tickLen, cy), tickPaint);
    // East
    canvas.drawLine(
        Offset(cx + radius - 2, cy), Offset(cx + radius - tickLen, cy), tickPaint);
  }

  @override
  bool shouldRepaint(_PlateGuidePainter old) => false;
}

// Shown on first launch BEFORE triggering the OS permission dialog.
// Our branded rationale screen gives context, then the user's tap triggers
// the actual system dialog — dramatically improving grant rates vs. a cold
// OS dialog with no explanation.
class _CameraRationaleScreen extends ConsumerWidget {
  const _CameraRationaleScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated icon container
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: AppColors.accent,
                size: 48,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'tavera.',
              style: AppTextStyles.displayLarge.copyWith(
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Point. Snap. Done.',
              style: AppTextStyles.titleLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Tavera uses your camera to instantly identify food and estimate '
              'calories with AI. We only process the photo you choose to log — '
              'no video is ever recorded or stored.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white60,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            // Feature rows
            ...[
              (Icons.bolt_rounded, 'Instant AI recognition'),
              (Icons.lock_outline_rounded, 'Photos processed securely'),
              (Icons.no_photography_outlined, 'No video, ever'),
            ].map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(item.$1, color: AppColors.accent, size: 18),
                    const SizedBox(width: 12),
                    Text(
                      item.$2,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () => ref
                  .read(cameraControllerProvider.notifier)
                  .requestPermission(),
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Allow Camera Access'),
            ),
          ],
        ),
      ),
    );
  }
}

// Shown when camera permission has been denied. Explains why we need it
// and deep-links to the OS Settings page so the user can enable it without
// having to find the app manually.
class _CameraPermissionScreen extends ConsumerWidget {
  const _CameraPermissionScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt_outlined,
                color: AppColors.accent,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Camera access needed',
              style: AppTextStyles.titleLarge.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Tavera uses your camera to identify food and estimate calories. '
              'We never store video — only the photo you choose to log.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white60,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            ElevatedButton.icon(
              onPressed: () async {
                // openAppSettings() deep-links to this app's iOS/Android
                // settings page where the user can toggle camera access.
                await openAppSettings();
              },
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Open Settings'),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () =>
                  ref.invalidate(cameraControllerProvider),
              child: Text(
                'I\'ve enabled it — try again',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── UI controls ───────────────────────────────────────────────────────────────

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// Water quick-add button — tap adds 250 ml; long-press shows options menu
// to subtract or reset. Mirrors the gallery button on the opposite side of
// the shutter so the capture button stays perfectly centred.
class _WaterButton extends ConsumerWidget {
  const _WaterButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ml = ref.watch(waterMlProvider);
    final hasWater = ml > 0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(waterMlProvider.notifier).add();
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          // No currentMl param — sheet watches waterMlProvider directly
          // so the displayed total stays live as the user taps +/−.
          builder: (_) => const _WaterSheet(),
        );
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: hasWater
              ? const Color(0xFF29ABE2).withValues(alpha: 0.35)
              : Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: hasWater
              ? Border.all(
                  color: const Color(0xFF29ABE2).withValues(alpha: 0.6),
                  width: 1.5,
                )
              : null,
        ),
        child: const Icon(Icons.water_drop_outlined,
            color: Colors.white, size: 18),
      ),
    );
  }
}

class _WaterSheet extends ConsumerWidget {
  const _WaterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch directly — updates live when the user taps +/− inside the sheet.
    final currentMl = ref.watch(waterMlProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHandle(),
          const SizedBox(height: 20),

          const Icon(Icons.water_drop_rounded,
              color: Color(0xFF29ABE2), size: 36),
          const SizedBox(height: 12),

          Text(
            '${(currentMl / 1000).toStringAsFixed(1)}L today',
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Each tap adds 250 ml (one glass)',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref.read(waterMlProvider.notifier).subtract();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.remove_rounded, size: 16),
                  label: const Text('−250 ml'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ref.read(waterMlProvider.notifier).add();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('+250 ml'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              ref.read(waterMlProvider.notifier).reset();
              Navigator.of(context).pop();
            },
            child: Text(
              'Reset to zero',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// _DailyChip — circular progress ring showing kcal vs. goal.
// The ring completes a full 360° arc when the user hits their goal.
// Tapping navigates to history; the ring turns red when the goal is exceeded.
class _DailyChip extends ConsumerWidget {
  final AsyncValue<DailyLogState> logState;
  final UserProfile? profile;
  const _DailyChip({required this.logState, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waterMl = ref.watch(waterMlProvider);

    return logState.when(
      data: (state) {
        final goal = profile?.calorieGoal ?? 2000;
        final progress = (state.totalCalories / goal).clamp(0.0, 1.0);
        final exceeded = state.totalCalories > goal;

        return GestureDetector(
          onTap: () => context.push('/history'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Circular progress arc
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CustomPaint(
                    painter: _RingPainter(
                      progress: progress,
                      exceeded: exceeded,
                    ),
                    child: Center(
                      child: Text(
                        '${state.logCount}',
                        style: TextStyle(
                          color: exceeded ? AppColors.danger : AppColors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${state.totalCalories} kcal',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                    if (waterMl > 0)
                      Text(
                        '💧 ${(waterMl / 1000).toStringAsFixed(1)}L',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final bool exceeded;
  const _RingPainter({required this.progress, required this.exceeded});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 3.0;
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    const startAngle = -1.5707963267948966; // -π/2 = 12 o'clock

    // Background track
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    if (progress <= 0) return;

    // Progress arc
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      startAngle,
      6.283185307179586 * progress, // 2π × progress
      false,
      Paint()
        ..color = exceeded ? AppColors.danger : AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.exceeded != exceeded;
}

// ─── Capture button ────────────────────────────────────────────────────────────

class _CaptureButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isCapturing;
  final Animation<double> pulseAnim;

  const _CaptureButton({
    required this.onTap,
    required this.isCapturing,
    required this.pulseAnim,
  });

  @override
  State<_CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<_CaptureButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.isCapturing) return;
    _scaleCtrl.forward().then((_) => _scaleCtrl.reverse());
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (_, child) =>
            Transform.scale(scale: _scaleAnim.value, child: child),
        child: SizedBox(
          width: 84,
          height: 84,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.9),
                    width: 3,
                  ),
                ),
              ),
              // Inner fill — white circle
              Container(
                width: 66,
                height: 66,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
