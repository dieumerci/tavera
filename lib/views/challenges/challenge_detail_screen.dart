import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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

        // ── Your progress card ───────────────────────────────────────────
        if (myParticipation.userId.isNotEmpty) ...[
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

        const SliverToBoxAdapter(child: SizedBox(height: 48)),
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
