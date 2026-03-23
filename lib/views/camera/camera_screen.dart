import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/camera_controller.dart';
import '../../controllers/log_controller.dart';
import '../../controllers/meal_controller.dart';
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
            data: (cam) => cam.isReady
                ? _CameraPreviewFill(controller: cam.controller!)
                : _CameraPlaceholder(message: cam.error ?? 'Camera unavailable'),
            loading: () => const _CameraPlaceholder(message: null),
            error: (e, _) => _CameraPlaceholder(message: e.toString()),
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
                  // Mirror spacer keeps capture button visually centred
                  const SizedBox(width: 36),
                  const SizedBox(width: 40),
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

class _DailyChip extends StatelessWidget {
  final AsyncValue<DailyLogState> logState;
  final dynamic profile;
  const _DailyChip({required this.logState, required this.profile});

  @override
  Widget build(BuildContext context) {
    return logState.when(
      data: (state) {
        final isPremium = profile?.isPremium == true;
        final limitLabel = isPremium ? '∞' : '3';
        return GestureDetector(
          onTap: () => context.push('/history'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${state.totalCalories} kcal',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: Colors.white, fontSize: 13),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 1,
                  height: 12,
                  color: Colors.white24,
                ),
                Text(
                  '${state.logCount}/$limitLabel',
                  style: AppTextStyles.caption.copyWith(color: Colors.white60),
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
