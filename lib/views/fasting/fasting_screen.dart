// ─── Fasting Screen ───────────────────────────────────────────────────────────
//
// Intermittent fasting timer. Shows a countdown ring while a fast is active,
// a protocol picker when idle, and a history list of recent completed fasts.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../controllers/fasting_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/fasting_session.dart';
import '../../services/haptic_service.dart';

class FastingScreen extends ConsumerWidget {
  const FastingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fastAsync = ref.watch(fastingControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Intermittent Fasting'),
        centerTitle: true,
      ),
      body: fastAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
        error: (e, _) => Center(
          child: Text(e.toString(), style: AppTextStyles.bodyMedium),
        ),
        data: (session) => _FastingBody(session: session),
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _FastingBody extends ConsumerStatefulWidget {
  final FastingSession? session;
  const _FastingBody({required this.session});

  @override
  ConsumerState<_FastingBody> createState() => _FastingBodyState();
}

class _FastingBodyState extends ConsumerState<_FastingBody> {
  Timer? _ticker;
  FastingProtocol _selectedProtocol = FastingProtocol.h16_8;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void didUpdateWidget(_FastingBody old) {
    super.didUpdateWidget(old);
    if (widget.session != old.session) _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    if (widget.session?.isActive == true) {
      // Tick every second to keep the ring and countdown live.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _startFast() async {
    setState(() => _acting = true);
    HapticService.medium();
    await ref
        .read(fastingControllerProvider.notifier)
        .start(_selectedProtocol);
    if (mounted) setState(() => _acting = false);
  }

  Future<void> _stopFast() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('End fast early?', style: AppTextStyles.titleMedium),
        content: Text(
          'Your progress will be saved, but the fast will be marked as incomplete.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('End fast',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _acting = true);
    HapticService.medium();
    await ref.read(fastingControllerProvider.notifier).stop();
    if (mounted) setState(() => _acting = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final isActive = session?.isActive == true;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        // ── Protocol picker (hidden when a fast is active) ─────────────────
        if (!isActive) ...[
          _SectionLabel('Choose protocol'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: FastingProtocol.values.map((p) {
              final selected = p == _selectedProtocol;
              return GestureDetector(
                onTap: () {
                  HapticService.selection();
                  setState(() => _selectedProtocol = p);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accent : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? AppColors.accent
                          : AppColors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.label,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: selected
                              ? AppColors.background
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.description,
                        style: AppTextStyles.caption.copyWith(
                          color: selected
                              ? AppColors.background.withValues(alpha: 0.8)
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
        ],

        // ── Active fast banner ─────────────────────────────────────────────
        if (isActive) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accentMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined,
                    size: 14, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(
                  '${session!.protocol.label} fast in progress',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // ── Ring timer ─────────────────────────────────────────────────────
        Center(
          child: _RingTimer(session: session, protocol: _selectedProtocol),
        ),

        const SizedBox(height: 28),

        // ── Action button ──────────────────────────────────────────────────
        ElevatedButton(
          onPressed: _acting
              ? null
              : (isActive ? _stopFast : _startFast),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isActive ? AppColors.danger : AppColors.accent,
            foregroundColor: AppColors.background,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          child: _acting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.background),
                )
              : Text(
                  isActive ? 'End Fast' : 'Start ${_selectedProtocol.label} Fast',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.background,
                  ),
                ),
        ),

        const SizedBox(height: 36),

        // ── History ────────────────────────────────────────────────────────
        _FastingHistory(),
      ],
    );
  }
}

// ─── Ring Timer ───────────────────────────────────────────────────────────────
//
// Shows a countdown arc. When no fast is active, renders an idle ring.
// Uses CustomPainter — Flutter's built-in progress indicator can't host
// center text or dual-arc styling.

class _RingTimer extends StatelessWidget {
  final FastingSession? session;
  final FastingProtocol protocol;
  const _RingTimer({required this.session, required this.protocol});

  @override
  Widget build(BuildContext context) {
    final isActive = session?.isActive == true;
    final progress = session?.progress ?? 0.0;
    final goalReached = session?.isGoalReached ?? false;

    final elapsed = session?.elapsed ?? Duration.zero;
    final remaining = session?.remaining ?? Duration.zero;

    final ringColor = goalReached
        ? AppColors.success
        : isActive
            ? AppColors.accent
            : AppColors.border;

    return SizedBox(
      width: 220,
      height: 220,
      child: CustomPaint(
        painter: _RingPainter(
          progress: isActive ? progress : 0.0,
          color: ringColor,
          trackColor: AppColors.surface,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive) ...[
                Text(
                  _formatDuration(elapsed),
                  style: AppTextStyles.calorieDisplay.copyWith(fontSize: 36),
                ),
                Text('elapsed', style: AppTextStyles.caption),
                const SizedBox(height: 8),
                Container(height: 1, width: 48, color: AppColors.border),
                const SizedBox(height: 8),
                if (!goalReached) ...[
                  Text(
                    _formatDuration(remaining),
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text('remaining', style: AppTextStyles.caption),
                ] else ...[
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 26),
                  const SizedBox(height: 4),
                  Text(
                    'Goal reached!',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ] else ...[
                Text(
                  protocol.label,
                  style: AppTextStyles.calorieDisplay.copyWith(fontSize: 40),
                ),
                const SizedBox(height: 4),
                Text(
                  '${protocol.fastHours}h fast',
                  style: AppTextStyles.caption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${h}h ${m}m';
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (size.width / 2) - 12;
    final strokeWidth = 14.0;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    // Full track ring
    canvas.drawCircle(Offset(cx, cy), radius, trackPaint);

    // Progress arc — starts at top (−π/2), sweeps clockwise
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

// ─── History ──────────────────────────────────────────────────────────────────

class _FastingHistory extends ConsumerWidget {
  const _FastingHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(fastingHistoryProvider);

    return historyAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (sessions) {
        if (sessions.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('Recent fasts'),
            const SizedBox(height: 10),
            ...sessions.map((s) => _HistoryRow(session: s)),
          ],
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final FastingSession session;
  const _HistoryRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        DateFormat('EEE, MMM d · h:mm a').format(session.startedAt);
    final duration = session.elapsed;
    final goal = session.fastDuration;
    final completed = duration >= goal;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: completed
                  ? AppColors.success.withValues(alpha: 0.12)
                  : AppColors.border.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              completed
                  ? Icons.check_rounded
                  : Icons.timer_off_outlined,
              size: 18,
              color: completed ? AppColors.success : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.protocol.label,
                    style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(dateLabel, style: AppTextStyles.caption),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${duration.inHours}h ${duration.inMinutes.remainder(60)}m',
                style: AppTextStyles.labelLarge.copyWith(
                  color: completed ? AppColors.success : AppColors.textSecondary,
                ),
              ),
              Text(
                completed ? 'Completed' : 'Ended early',
                style: AppTextStyles.caption.copyWith(
                  color: completed ? AppColors.success : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.caption.copyWith(letterSpacing: 0.8),
    );
  }
}
