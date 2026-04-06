import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../controllers/challenge_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/challenge.dart';
import '../../services/haptic_service.dart';
import '../../widgets/tavera_loading.dart';

// ─── ChallengeDetailScreen ────────────────────────────────────────────────────
//
// Shows the full challenge detail: progress summary, leaderboard,
// invite code sharing, and challenge info.

class ChallengeDetailScreen extends ConsumerWidget {
  final String challengeId;
  const ChallengeDetailScreen({super.key, required this.challengeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync =
        ref.watch(challengeDetailProvider(challengeId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: detailAsync.when(
        loading: () => const _LoadingScaffold(),
        error: (e, _) => _ErrorScaffold(error: e.toString()),
        data: (challenge) {
          if (challenge == null) {
            return _ErrorScaffold(error: 'Challenge not found.');
          }
          return _ChallengeContent(challenge: challenge);
        },
      ),
    );
  }
}

// ─── Main content ─────────────────────────────────────────────────────────────

class _ChallengeContent extends ConsumerWidget {
  final Challenge challenge;
  const _ChallengeContent({required this.challenge});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId =
        ref.read(userProfileProvider).valueOrNull?.id ?? '';

    final myParticipation = challenge.participants.firstWhere(
      (p) => p.userId == currentUserId,
      orElse: () => ChallengeParticipant(
        id: '',
        challengeId: challenge.id,
        userId: '',
        displayName: 'You',
        score: 0,
        streakDays: 0,
        rank: 0,
        joinedAt: DateTime.now(),
      ),
    );

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Header ───────────────────────────────────────────────────────
        _ChallengeAppBar(challenge: challenge),

        // ── Completion banner (animated, appears for completed challenges) ─
        if (challenge.isCompleted && myParticipation.userId.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _CompletionBanner(
                challenge: challenge,
                participant: myParticipation,
              ),
            ),
          ),

        // ── Your progress card ───────────────────────────────────────────
        if (myParticipation.userId.isNotEmpty && !challenge.isCompleted) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _MyProgressCard(
                participant: myParticipation,
                challenge: challenge,
              ),
            ),
          ),
        ],

        // ── Challenge info ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _InfoCard(challenge: challenge),
          ),
        ),

        // ── Leaderboard ───────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text('Leaderboard', style: AppTextStyles.titleMedium),
          ),
        ),

        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final participant = challenge.participants[i];
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: _LeaderboardRow(
                  participant: participant,
                  isMe: participant.userId == currentUserId,
                ),
              );
            },
            childCount: challenge.participants.length,
          ),
        ),

        // Invite section (only for creator or private challenges)
        if (!challenge.isPublic || challenge.creatorId == currentUserId)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _InviteSection(challenge: challenge),
            ),
          ),

        // Leave button (non-creator participants on active/upcoming challenges)
        if (myParticipation.userId.isNotEmpty &&
            challenge.creatorId != currentUserId &&
            !challenge.isCompleted)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _LeaveButton(challengeId: challenge.id),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 48)),
      ],
    );
  }
}

// ─── Confetti particle model ──────────────────────────────────────────────────

class _Particle {
  double x; // 0.0–1.0 relative to widget width
  double y; // 0.0–1.0 relative to widget height
  double vx;
  double vy;
  double angle;
  double spin;
  Color color;
  double size;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.angle,
    required this.spin,
    required this.color,
    required this.size,
  });
}

// ─── Confetti painter ─────────────────────────────────────────────────────────

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double opacity;

  _ConfettiPainter(this.particles, this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(p.x * size.width, p.y * size.height);
      canvas.rotate(p.angle);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => true;
}

// ─── Completion banner ────────────────────────────────────────────────────────
//
// Slides in with a scale + fade animation. Confetti particles rain down for
// 2.5 seconds then fade out. Shows the user's final rank and score, plus a
// "Share results" button that invokes the native iOS/Android share sheet.

class _CompletionBanner extends StatefulWidget {
  final Challenge challenge;
  final ChallengeParticipant participant;
  const _CompletionBanner(
      {required this.challenge, required this.participant});

  @override
  State<_CompletionBanner> createState() => _CompletionBannerState();
}

class _CompletionBannerState extends State<_CompletionBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confettiCtrl;
  late final List<_Particle> _particles;
  final _rng = math.Random();

  static const _colors = [
    Color(0xFFFFD700), // gold
    Color(0xFFCCFF90), // accent lime
    Color(0xFFFF6B6B), // coral
    Color(0xFF64B5F6), // blue
    Color(0xFFFF80AB), // pink
    Color(0xFFB388FF), // purple
  ];

  @override
  void initState() {
    super.initState();
    _particles = List.generate(60, (_) => _Particle(
      x: _rng.nextDouble(),
      y: -0.1 - _rng.nextDouble() * 0.4, // start above the banner
      vx: (_rng.nextDouble() - 0.5) * 0.008,
      vy: 0.004 + _rng.nextDouble() * 0.006,
      angle: _rng.nextDouble() * math.pi * 2,
      spin: (_rng.nextDouble() - 0.5) * 0.15,
      color: _colors[_rng.nextInt(_colors.length)],
      size: 6 + _rng.nextDouble() * 6,
    ));

    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..addListener(() {
        setState(() {
          for (final p in _particles) {
            p.x += p.vx;
            p.y += p.vy;
            p.angle += p.spin;
            // wrap horizontally
            if (p.x < 0) p.x += 1.0;
            if (p.x > 1) p.x -= 1.0;
          }
        });
      })
      ..forward();
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    super.dispose();
  }

  String _buildShareText() {
    final p = widget.participant;
    final c = widget.challenge;
    final rank = p.rank > 0 ? '#${p.rank}' : 'a participant';
    final score = p.score.toStringAsFixed(0);
    final streak = p.streakDays;
    final start = DateFormat('MMM d').format(c.startDate);
    final end = DateFormat('MMM d').format(c.endDate);

    return '''
🏆 I just completed a challenge on Tavera!

${c.type.icon} ${c.title}
📅 $start – $end
🎯 Goal: ${c.targetValue.toStringAsFixed(0)} ${c.type == ChallengeType.calorieBudget ? 'kcal/day' : c.type == ChallengeType.streak ? 'day streak' : c.type == ChallengeType.macroTarget ? 'g protein/day' : 'pts'}
🏅 Final rank: $rank
⭐ Score: $score pts${streak > 0 ? '\n🔥 Best streak: $streak days' : ''}

Track your nutrition with Tavera — AI-powered calorie tracking 📱
''';
  }

  String _rankLabel(int rank) => switch (rank) {
        1 => '🥇 1st Place',
        2 => '🥈 2nd Place',
        3 => '🥉 3rd Place',
        _ => rank > 0 ? '#$rank Place' : 'Completed',
      };

  @override
  Widget build(BuildContext context) {
    final confettiOpacity =
        (1.0 - _confettiCtrl.value).clamp(0.0, 1.0);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // ── Banner content ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFFD700).withValues(alpha: 0.15),
                    AppColors.accent.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  // Trophy row
                  Row(
                    children: [
                      const Text('🏆', style: TextStyle(fontSize: 36)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Challenge Complete!',
                              style: AppTextStyles.titleMedium.copyWith(
                                color: const Color(0xFFFFD700),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.challenge.title,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatBadge(
                        label: 'Final rank',
                        value: _rankLabel(widget.participant.rank),
                      ),
                      _StatBadge(
                        label: 'Score',
                        value: '${widget.participant.score.toStringAsFixed(0)} pts',
                      ),
                      if (widget.participant.streakDays > 0)
                        _StatBadge(
                          label: 'Best streak',
                          value: '${widget.participant.streakDays}d 🔥',
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Share button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticService.medium();
                        Share.share(_buildShareText(),
                            subject: 'I completed a Tavera challenge!');
                      },
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('Share my results'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFFFFD700).withValues(alpha: 0.15),
                        foregroundColor: const Color(0xFFFFD700),
                        elevation: 0,
                        side: BorderSide(
                            color: const Color(0xFFFFD700)
                                .withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Confetti overlay (fades out after 2.5s) ─────────────────
            if (_confettiCtrl.value < 1.0)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ConfettiPainter(_particles, confettiOpacity),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  const _StatBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 2),
        Text(label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 10,
            )),
      ],
    );
  }
}

// ─── App bar (collapses into title) ──────────────────────────────────────────

class _ChallengeAppBar extends StatelessWidget {
  final Challenge challenge;
  const _ChallengeAppBar({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final daysLeft = challenge.daysRemaining;
    final statusText = challenge.isCompleted
        ? 'Ended'
        : challenge.isUpcoming
            ? 'Starts ${DateFormat('MMM d').format(challenge.startDate)}'
            : '$daysLeft day${daysLeft == 1 ? '' : 's'} remaining';

    return SliverAppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        onPressed: () {
          HapticService.selection();
          context.pop();
        },
      ),
      title: Text(challenge.title, style: AppTextStyles.titleMedium),
      expandedHeight: 140,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: AppColors.background,
          padding: const EdgeInsets.fromLTRB(20, 80, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                children: [
                  Text(challenge.type.icon,
                      style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(challenge.type.label,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary)),
                      Text(statusText,
                          style: AppTextStyles.caption.copyWith(
                            color: challenge.isCompleted
                                ? AppColors.textTertiary
                                : AppColors.accent,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── My progress card ─────────────────────────────────────────────────────────

class _MyProgressCard extends StatelessWidget {
  final ChallengeParticipant participant;
  final Challenge challenge;
  const _MyProgressCard(
      {required this.participant, required this.challenge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.15),
            AppColors.accent.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                participant.rank > 0 ? '#${participant.rank}' : '–',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.accent,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your progress', style: AppTextStyles.caption),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      participant.score.toStringAsFixed(0),
                      style: AppTextStyles.calorieDisplay.copyWith(
                        fontSize: 26,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('pts', style: AppTextStyles.bodyMedium),
                  ],
                ),
                if (participant.streakDays > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${participant.streakDays} day streak 🔥',
                    style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Challenge info card ──────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final Challenge challenge;
  const _InfoCard({required this.challenge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (challenge.description.isNotEmpty) ...[
            Text(challenge.description,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: 14),
            const Divider(color: AppColors.border),
            const SizedBox(height: 14),
          ],
          _InfoRow(
            label: 'Target',
            value: '${challenge.targetValue.toStringAsFixed(0)} '
                '${challenge.type == ChallengeType.calorieBudget ? 'kcal/day' : challenge.type == ChallengeType.streak ? 'days' : challenge.type == ChallengeType.macroTarget ? 'g protein/day' : 'pts'}',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Duration',
            value:
                '${DateFormat('MMM d').format(challenge.startDate)} – ${DateFormat('MMM d').format(challenge.endDate)}',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Visibility',
            value: challenge.isPublic ? 'Public' : 'Private (invite only)',
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.caption),
        Text(value,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}

// ─── Leaderboard row ──────────────────────────────────────────────────────────

class _LeaderboardRow extends StatelessWidget {
  final ChallengeParticipant participant;
  final bool isMe;
  const _LeaderboardRow(
      {required this.participant, required this.isMe});

  String _rankEmoji(int rank) => switch (rank) {
        1 => '🥇',
        2 => '🥈',
        3 => '🥉',
        _ => '$rank.',
      };

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isMe
            ? AppColors.accent.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? AppColors.accent.withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 32,
            child: Text(
              participant.rank > 0 ? _rankEmoji(participant.rank) : '–',
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 12),

          // Avatar / initials
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isMe
                  ? AppColors.accent.withValues(alpha: 0.2)
                  : AppColors.card,
              shape: BoxShape.circle,
            ),
            child: participant.avatarUrl != null
                ? ClipOval(
                    child: Image.network(participant.avatarUrl!,
                        fit: BoxFit.cover))
                : Center(
                    child: Text(
                      participant.displayName.isNotEmpty
                          ? participant.displayName[0].toUpperCase()
                          : '?',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: isMe
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),

          // Name
          Expanded(
            child: Text(
              isMe ? '${participant.displayName} (you)' : participant.displayName,
              style: AppTextStyles.labelLarge.copyWith(
                color: isMe ? AppColors.accent : AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Score
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                participant.score.toStringAsFixed(0),
                style: AppTextStyles.labelLarge.copyWith(
                  color: isMe ? AppColors.accent : AppColors.textPrimary,
                  fontSize: 16,
                ),
              ),
              if (participant.streakDays > 0)
                Text(
                  '🔥 ${participant.streakDays}',
                  style: AppTextStyles.caption.copyWith(fontSize: 10),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Invite section ───────────────────────────────────────────────────────────

class _InviteSection extends StatelessWidget {
  final Challenge challenge;
  const _InviteSection({required this.challenge});

  @override
  Widget build(BuildContext context) {
    if (challenge.inviteCode.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invite friends', style: AppTextStyles.labelLarge),
          const SizedBox(height: 4),
          Text(
            'Share this code to invite people to this private challenge.',
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    challenge.inviteCode,
                    style: AppTextStyles.titleMedium.copyWith(
                      letterSpacing: 4,
                      color: AppColors.accent,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () {
                  HapticService.medium();
                  Clipboard.setData(
                      ClipboardData(text: challenge.inviteCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invite code copied!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded,
                    color: AppColors.textSecondary),
                tooltip: 'Copy code',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Leave button ─────────────────────────────────────────────────────────────

class _LeaveButton extends ConsumerStatefulWidget {
  final String challengeId;
  const _LeaveButton({required this.challengeId});

  @override
  ConsumerState<_LeaveButton> createState() => _LeaveButtonState();
}

class _LeaveButtonState extends ConsumerState<_LeaveButton> {
  bool _leaving = false;

  Future<void> _confirmAndLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Leave challenge?', style: AppTextStyles.titleMedium),
        content: Text(
          'Your progress will be removed from the leaderboard.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Leave',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _leaving = true);
    HapticService.medium();

    final success = await ref
        .read(myChallengesProvider.notifier)
        .leave(widget.challengeId);

    if (!mounted) return;
    if (success) {
      context.pop();
    } else {
      setState(() => _leaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to leave challenge. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: _leaving ? null : _confirmAndLeave,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.danger,
        side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: _leaving
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.danger,
              ),
            )
          : const Text('Leave challenge'),
    );
  }
}

// ─── Loading / error scaffolds ────────────────────────────────────────────────

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: const Center(child: TaveraLoading()),
    );
  }
}

class _ErrorScaffold extends StatelessWidget {
  final String error;
  const _ErrorScaffold({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.danger, size: 36),
              const SizedBox(height: 12),
              Text('Something went wrong', style: AppTextStyles.titleMedium),
              const SizedBox(height: 8),
              Text(error,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
