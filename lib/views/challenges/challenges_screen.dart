import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controllers/challenge_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/challenge.dart';
import '../../services/haptic_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/tavera_loading.dart';
import '../paywall/paywall_sheet.dart';
import 'create_challenge_sheet.dart';

// ─── ChallengesScreen ─────────────────────────────────────────────────────────
//
// Two-tab screen:
//   "My Challenges"  — challenges the user participates in
//   "Discover"       — public challenges available to join

class ChallengesScreen extends ConsumerStatefulWidget {
  const ChallengesScreen({super.key});

  @override
  ConsumerState<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends ConsumerState<ChallengesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _showCreateSheet() {
    if (!SubscriptionService.canCreateChallenge(ref)) {
      _showUpgradeDialog();
      return;
    }
    HapticService.medium();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateChallengeSheet(),
    );
  }

  void _showJoinDialog() {
    HapticService.selection();
    final codeCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Join with invite code', style: AppTextStyles.titleMedium),
        content: TextField(
          controller: codeCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: AppTextStyles.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Enter 6-char code',
            hintStyle: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticService.selection();
              Navigator.of(ctx).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              HapticService.heavy();
              Navigator.of(ctx).pop();
              final success = await ref
                  .read(myChallengesProvider.notifier)
                  .join(inviteCode: codeCtrl.text);
              if (mounted && !success) {
                _showErrorSnack('Invite code not found. Please check and try again.');
              }
            },
            child: Text(
              'Join',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  void _showUpgradeDialog() {
    HapticService.error();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Premium required', style: AppTextStyles.titleMedium),
        content: Text(
          'Creating challenges requires a Tavera Premium subscription. Upgrade to challenge your friends!',
          style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticService.selection();
              Navigator.of(ctx).pop();
            },
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () {
              HapticService.heavy();
              Navigator.of(ctx).pop();
              showPaywallSheet(context);
            },
            child: Text('Upgrade', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  void _showErrorSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () {
            HapticService.selection();
            context.pop();
          },
        ),
        title: const Text('Challenges'),
        actions: [
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined, size: 20),
            onPressed: _showJoinDialog,
            tooltip: 'Join with code',
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 24),
            onPressed: _showCreateSheet,
            tooltip: 'Create challenge',
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: AppTextStyles.labelLarge.copyWith(fontSize: 14),
          onTap: (_) => HapticService.selection(),
          tabs: const [
            Tab(text: 'My Challenges'),
            Tab(text: 'Discover'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _MyChallengesList(),
          _PublicChallengesList(),
        ],
      ),
    );
  }
}

// ─── My challenges ────────────────────────────────────────────────────────────

class _MyChallengesList extends ConsumerWidget {
  const _MyChallengesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myChallengesProvider);
    return async.when(
      loading: () => const Center(child: TaveraLoading()),
      error: (e, _) => _ErrorState(error: e.toString()),
      data: (challenges) {
        if (challenges.isEmpty) {
          return _EmptyState(
            message: "You're not in any challenges yet.",
            sub: 'Create one or join with an invite code.',
            icon: Icons.emoji_events_rounded,
          );
        }
        return RefreshIndicator(
          color: AppColors.accent,
          onRefresh: () =>
              ref.read(myChallengesProvider.notifier).refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            itemCount: challenges.length,
            itemBuilder: (_, i) => _ChallengeCard(
              challenge: challenges[i],
              showJoinButton: false,
            ),
          ),
        );
      },
    );
  }
}

// ─── Public challenges ────────────────────────────────────────────────────────

class _PublicChallengesList extends ConsumerWidget {
  const _PublicChallengesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(publicChallengesProvider);
    return async.when(
      loading: () => const Center(child: TaveraLoading()),
      error: (e, _) => _ErrorState(error: e.toString()),
      data: (challenges) {
        if (challenges.isEmpty) {
          return _EmptyState(
            message: 'No public challenges right now.',
            sub: 'Create the first one!',
            icon: Icons.public_rounded,
          );
        }
        return RefreshIndicator(
          color: AppColors.accent,
          onRefresh: () =>
              ref.read(publicChallengesProvider.notifier).refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            itemCount: challenges.length,
            itemBuilder: (_, i) => _ChallengeCard(
              challenge: challenges[i],
              showJoinButton: true,
            ),
          ),
        );
      },
    );
  }
}

// ─── Challenge card ───────────────────────────────────────────────────────────

class _ChallengeCard extends ConsumerWidget {
  final Challenge challenge;
  final bool showJoinButton;
  const _ChallengeCard({required this.challenge, required this.showJoinButton});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daysLeft = challenge.daysRemaining;

    return GestureDetector(
      onTap: () {
        HapticService.selection();
        context.push('/challenges/${challenge.id}');
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(challenge.type.icon,
                    style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        challenge.title,
                        style: AppTextStyles.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        challenge.type.label,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showJoinButton) ...[
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      HapticService.heavy();
                      await ref
                          .read(myChallengesProvider.notifier)
                          .join(challengeId: challenge.id);
                      ref.invalidate(publicChallengesProvider);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Join',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ],
            ),
            if (challenge.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                challenge.description,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _ChipPill(
                  icon: Icons.timer_outlined,
                  label: challenge.isCompleted
                      ? 'Ended'
                      : challenge.isUpcoming
                          ? 'Upcoming'
                          : '$daysLeft day${daysLeft == 1 ? '' : 's'} left',
                  color: challenge.isCompleted
                      ? AppColors.textTertiary
                      : AppColors.accent,
                ),
                const SizedBox(width: 8),
                _ChipPill(
                  icon: Icons.people_outline_rounded,
                  label: '${challenge.participants.length} joined',
                  color: AppColors.textSecondary,
                ),
                if (!challenge.isPublic) ...[
                  const SizedBox(width: 8),
                  _ChipPill(
                    icon: Icons.lock_outline_rounded,
                    label: 'Private',
                    color: AppColors.textSecondary,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ChipPill(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(color: color, fontSize: 11),
        ),
      ],
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final String sub;
  final IconData icon;
  const _EmptyState(
      {required this.message, required this.sub, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(icon, color: AppColors.textSecondary, size: 36),
            ),
            const SizedBox(height: 20),
            Text(message, style: AppTextStyles.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(sub, style: AppTextStyles.bodyMedium,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
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
    );
  }
}
