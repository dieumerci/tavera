import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../controllers/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

// Three logical views within the same route:
//   auth  → sign-up / sign-in form
//   goal  → calorie goal picker (shown after successful sign-up)
//   (navigation to /camera is handled by the router redirect)
enum _OnboardingStep { auth, goal }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl     = TextEditingController();

  bool _isSignUp = true;
  bool _isLoading = false;
  String? _error;

  // Calorie goal step
  _OnboardingStep _step = _OnboardingStep.auth;
  int _calorieGoal = 2000;

  // Preset goal buckets shown as tappable chips.
  static const _goalPresets = [1500, 1800, 2000, 2500, 3000];

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── Auth submission ─────────────────────────────────────────────────────────

  Future<void> _submitAuth() async {
    if (_emailCtrl.text.trim().isEmpty || _passwordCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_isSignUp) {
        final pendingEmail = await ref
            .read(authControllerProvider.notifier)
            .signUpWithEmail(
              _emailCtrl.text.trim(),
              _passwordCtrl.text.trim(),
              _nameCtrl.text.trim(),
              // Pass a temporary default; the goal step will upsert the real
              // value immediately after before the router redirect fires.
              calorieGoal: _calorieGoal,
            );

        if (pendingEmail != null && mounted) {
          // Email confirmation required — tell the user.
          setState(() {
            _isLoading = false;
            _error =
                'Check your inbox at $pendingEmail and confirm your email, '
                'then sign in below.';
            _isSignUp = false;
          });
          return;
        }

        // Sign-up succeeded and session is live — show the goal picker
        // before the router redirect fires so the user can personalise
        // their target. The redirect is still registered; it fires after
        // setState() when the router re-evaluates.
        if (mounted) {
          setState(() {
            _isLoading = false;
            _step = _OnboardingStep.goal;
          });
        }
      } else {
        await ref.read(authControllerProvider.notifier).signInWithEmail(
              _emailCtrl.text.trim(),
              _passwordCtrl.text.trim(),
            );
        // Sign-in succeeded — router redirect to /camera handles navigation.
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Goal submission ─────────────────────────────────────────────────────────

  Future<void> _submitGoal() async {
    setState(() => _isLoading = true);
    try {
      // Session is guaranteed at this point — sign-up already succeeded.
      // Update the profile row directly via the Supabase client; no need
      // to go through AuthController for a simple profile field update.
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({'calorie_goal': _calorieGoal})
            .eq('id', session.user.id);
      }
    } catch (_) {
      // Non-fatal — the default 2000 kcal written at sign-up is still valid.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    // Invalidate so the history screen picks up the real goal immediately.
    ref.invalidate(userProfileProvider);
    // Router redirect fires automatically because auth state has a session.
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _friendlyError(String raw) {
    if (raw.contains('Invalid login'))      return 'Wrong email or password';
    if (raw.contains('already registered')) return 'Account exists — sign in instead';
    if (raw.contains('Password should'))    return 'Password must be at least 6 characters';
    return 'Something went wrong. Try again.';
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          child: _step == _OnboardingStep.auth
              ? _AuthView(
                  key: const ValueKey('auth'),
                  emailCtrl: _emailCtrl,
                  passwordCtrl: _passwordCtrl,
                  nameCtrl: _nameCtrl,
                  isSignUp: _isSignUp,
                  isLoading: _isLoading,
                  error: _error,
                  onToggle: () => setState(() {
                    _isSignUp = !_isSignUp;
                    _error = null;
                  }),
                  onSubmit: _submitAuth,
                )
              : _GoalView(
                  key: const ValueKey('goal'),
                  selected: _calorieGoal,
                  presets: _goalPresets,
                  isLoading: _isLoading,
                  onSelected: (v) => setState(() => _calorieGoal = v),
                  onSubmit: _submitGoal,
                ),
        ),
      ),
    );
  }
}

// ─── Auth view ──────────────────────────────────────────────────────────────

class _AuthView extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController nameCtrl;
  final bool isSignUp;
  final bool isLoading;
  final String? error;
  final VoidCallback onToggle;
  final VoidCallback onSubmit;

  const _AuthView({
    super.key,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.nameCtrl,
    required this.isSignUp,
    required this.isLoading,
    required this.error,
    required this.onToggle,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 64),

          // Brand
          Text(
            'tavera.',
            style: AppTextStyles.displayLarge.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 10),
          Text(
            'Point your camera.\nTrack your calories.',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 56),

          // Sign-up / Sign-in toggle
          Row(
            children: [
              _TabButton(
                label: 'Create account',
                isActive: isSignUp,
                onTap: onToggle,
              ),
              const SizedBox(width: 24),
              _TabButton(
                label: 'Sign in',
                isActive: !isSignUp,
                onTap: onToggle,
              ),
            ],
          ),

          const SizedBox(height: 28),

          if (isSignUp) ...[
            _InputField(
              controller: nameCtrl,
              hint: 'Your name',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 12),
          ],
          _InputField(
            controller: emailCtrl,
            hint: 'Email address',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _InputField(
            controller: passwordCtrl,
            hint: 'Password',
            icon: Icons.lock_outline_rounded,
            obscureText: true,
          ),

          if (error != null) ...[
            const SizedBox(height: 14),
            Text(
              error!,
              style: AppTextStyles.caption.copyWith(
                color: error!.contains('Check your inbox')
                    ? AppColors.success
                    : AppColors.danger,
                height: 1.5,
              ),
            ),
          ],

          const SizedBox(height: 28),

          ElevatedButton(
            onPressed: isLoading ? null : onSubmit,
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.background,
                    ),
                  )
                : Text(isSignUp ? 'Get started' : 'Sign in'),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── Calorie goal view ──────────────────────────────────────────────────────

class _GoalView extends StatelessWidget {
  final int selected;
  final List<int> presets;
  final bool isLoading;
  final ValueChanged<int> onSelected;
  final VoidCallback onSubmit;

  const _GoalView({
    super.key,
    required this.selected,
    required this.presets,
    required this.isLoading,
    required this.onSelected,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 64),

          Text(
            'Set your goal',
            style:
                AppTextStyles.displayLarge.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 10),
          Text(
            'How many calories do you\naim to eat per day?',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 48),

          // Preset chips
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: presets.map((goal) {
              final isSelected = goal == selected;
              return GestureDetector(
                onTap: () => onSelected(goal),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    '$goal kcal',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: isSelected
                          ? AppColors.background
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 32),

          // Fine-tune slider
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Fine-tune', style: AppTextStyles.caption),
                  Text(
                    '$selected kcal / day',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                  activeTrackColor: AppColors.accent,
                  inactiveTrackColor: AppColors.border,
                  thumbColor: AppColors.accent,
                  overlayColor: AppColors.accent.withValues(alpha: 0.15),
                ),
                child: Slider(
                  value: selected.toDouble(),
                  min: 1200,
                  max: 4000,
                  divisions: 56, // 50 kcal steps
                  onChanged: (v) => onSelected(v.round()),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('1 200', style: AppTextStyles.caption),
                  Text('4 000', style: AppTextStyles.caption),
                ],
              ),
            ],
          ),

          const Spacer(),

          ElevatedButton(
            onPressed: isLoading ? null : onSubmit,
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.background,
                    ),
                  )
                : const Text('Start tracking'),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── Shared widgets ──────────────────────────────────────────────────────────

class _TabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: (isActive
                ? AppTextStyles.labelLarge
                : AppTextStyles.bodyMedium)
            .copyWith(
          color:
              isActive ? AppColors.textPrimary : AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType keyboardType;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: AppTextStyles.bodyLarge,
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTextStyles.bodyMedium,
          prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        ),
      ),
    );
  }
}
