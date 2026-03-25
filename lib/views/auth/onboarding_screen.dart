import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../controllers/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../services/haptic_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

// Three logical views within the same route:
//   auth  → sign-up / sign-in form
//   goal  → calorie goal picker (shown after successful sign-up)
//   (navigation to / is handled by context.go + router redirect)
enum _OnboardingStep { auth, goal }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl     = TextEditingController();

  bool _isSignUp = true;
  bool _isLoading = false;

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

  // ── Auth submission ──────────────────────────────────────────────────────────

  Future<void> _submitAuth() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final name     = _nameCtrl.text.trim();

    // Client-side validation
    if (_isSignUp && name.isEmpty) {
      await HapticService.error();
      _showErrorDialog('Please enter your name.');
      return;
    }
    if (email.isEmpty || password.isEmpty) {
      await HapticService.error();
      _showErrorDialog('Please fill in all fields.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      await HapticService.error();
      _showErrorDialog('Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      await HapticService.error();
      _showErrorDialog('Password must be at least 6 characters.');
      return;
    }

    await HapticService.medium();
    setState(() => _isLoading = true);

    try {
      if (_isSignUp) {
        final pendingEmail = await ref
            .read(authControllerProvider.notifier)
            .signUpWithEmail(
              email,
              password,
              name,
              calorieGoal: _calorieGoal,
            );

        if (!mounted) return;

        if (pendingEmail != null) {
          // Email confirmation required
          setState(() => _isLoading = false);
          _showInfoDialog(
            'Check your inbox',
            'A confirmation link was sent to $pendingEmail. '
            'Open it and then sign in below.',
            onDismiss: () => setState(() => _isSignUp = false),
          );
          return;
        }

        // Sign-up succeeded and session is live — show goal picker
        setState(() {
          _isLoading = false;
          _step = _OnboardingStep.goal;
        });
      } else {
        await ref.read(authControllerProvider.notifier).signInWithEmail(
              email,
              password,
            );
        if (!mounted) return;
        await HapticService.success();
        // Navigate to dashboard (/) — GoRouter redirect is a safety net,
        // but we drive explicitly to avoid the async stream gap.
        if (!mounted) return;
        context.go('/');
      }
    } catch (e) {
      if (!mounted) return;
      await HapticService.error();
      _showErrorDialog(_friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Goal submission ──────────────────────────────────────────────────────────

  Future<void> _submitGoal() async {
    await HapticService.heavy();
    setState(() => _isLoading = true);
    try {
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
    ref.invalidate(userProfileProvider);
    await HapticService.success();
    if (mounted) context.go('/');
  }

  // ── Error / info dialogs ─────────────────────────────────────────────────────

  void _showErrorDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Oops', style: AppTextStyles.titleMedium),
        content: Text(message, style: AppTextStyles.bodyMedium.copyWith(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () {
              HapticService.selection();
              Navigator.of(ctx).pop();
            },
            child: Text(
              'OK',
              style: AppTextStyles.labelLarge.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(String title, String message, {VoidCallback? onDismiss}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: AppTextStyles.titleMedium),
        content: Text(message, style: AppTextStyles.bodyMedium.copyWith(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () {
              HapticService.selection();
              Navigator.of(ctx).pop();
              onDismiss?.call();
            },
            child: Text(
              'Got it',
              style: AppTextStyles.labelLarge.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _friendlyError(String raw) {
    if (raw.contains('Invalid login') || raw.contains('invalid_credentials')) {
      return 'Wrong email or password. Please try again.';
    }
    if (raw.contains('already registered') || raw.contains('already been registered')) {
      return 'An account with this email already exists. Sign in instead.';
    }
    if (raw.contains('Password should') || raw.contains('password')) {
      return 'Password must be at least 6 characters.';
    }
    if (raw.contains('Unable to validate') || raw.contains('email')) {
      return 'Please enter a valid email address.';
    }
    if (raw.contains('network') || raw.contains('connection')) {
      return 'No internet connection. Please check your network and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  // ── Build ────────────────────────────────────────────────────────────────────

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
                  onToggle: () async {
                    await HapticService.selection();
                    setState(() {
                      _isSignUp = !_isSignUp;
                    });
                  },
                  onSubmit: _submitAuth,
                )
              : _GoalView(
                  key: const ValueKey('goal'),
                  selected: _calorieGoal,
                  presets: _goalPresets,
                  isLoading: _isLoading,
                  onSelected: (v) async {
                    await HapticService.selection();
                    setState(() => _calorieGoal = v);
                  },
                  onSubmit: _submitGoal,
                ),
        ),
      ),
    );
  }
}

// ─── Auth view ────────────────────────────────────────────────────────────────

class _AuthView extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController nameCtrl;
  final bool isSignUp;
  final bool isLoading;
  final VoidCallback onToggle;
  final VoidCallback onSubmit;

  const _AuthView({
    super.key,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.nameCtrl,
    required this.isSignUp,
    required this.isLoading,
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
            isSignUp
                ? 'Track calories.\nFaster than ever.'
                : 'Welcome back.\nLet\'s keep going.',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 48),

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

          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: isSignUp
                ? Column(
                    children: [
                      _InputField(
                        controller: nameCtrl,
                        hint: 'Your name',
                        icon: Icons.person_outline_rounded,
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          _InputField(
            controller: emailCtrl,
            hint: 'Email address',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _InputField(
            controller: passwordCtrl,
            hint: isSignUp ? 'Create a password (6+ chars)' : 'Password',
            icon: Icons.lock_outline_rounded,
            obscureText: true,
          ),

          const SizedBox(height: 28),

          // Primary CTA
          _PrimaryButton(
            label: isSignUp ? 'Get started' : 'Sign in',
            isLoading: isLoading,
            onTap: onSubmit,
          ),

          const SizedBox(height: 20),

          // Toggle link at bottom
          Center(
            child: GestureDetector(
              onTap: onToggle,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: isSignUp
                            ? 'Already have an account? '
                            : 'Don\'t have an account? ',
                        style: AppTextStyles.bodyMedium,
                      ),
                      TextSpan(
                        text: isSignUp ? 'Sign in' : 'Create one',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── Calorie goal view ────────────────────────────────────────────────────────

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
            style: AppTextStyles.displayLarge.copyWith(color: AppColors.accent),
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
                    color: isSelected ? AppColors.accent : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppColors.accent : AppColors.border,
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
                  divisions: 56,
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

          _PrimaryButton(
            label: 'Start tracking',
            isLoading: isLoading,
            onTap: onSubmit,
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

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
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: (isActive
                      ? AppTextStyles.labelLarge
                      : AppTextStyles.bodyMedium)
                  .copyWith(
                color: isActive
                    ? AppColors.textPrimary
                    : AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 2,
              width: isActive ? 100 : 0,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Stateful so we can own a FocusNode and fire haptics on focus.
class _InputField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  State<_InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<_InputField> {
  final _focusNode = FocusNode();
  bool _isFocused = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      final focused = _focusNode.hasFocus;
      if (focused) HapticService.selection();
      setState(() => _isFocused = focused);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isFocused ? AppColors.accent : AppColors.border,
          width: _isFocused ? 1.5 : 1.0,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        obscureText: widget.obscureText && !_showPassword,
        keyboardType: widget.keyboardType,
        textCapitalization: widget.textCapitalization,
        style: AppTextStyles.bodyLarge,
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textTertiary,
          ),
          prefixIcon: Icon(
            widget.icon,
            color: _isFocused ? AppColors.accent : AppColors.textSecondary,
            size: 20,
          ),
          suffixIcon: widget.obscureText
              ? GestureDetector(
                  onTap: () {
                    HapticService.selection();
                    setState(() => _showPassword = !_showPassword);
                  },
                  child: Icon(
                    _showPassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        ),
      ),
    );
  }
}

// ─── Primary Button ───────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : () {
          HapticService.heavy();
          onTap();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.background,
          disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.background,
                ),
              )
            : Text(
                label,
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.background,
                  fontSize: 16,
                ),
              ),
      ),
    );
  }
}
