import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isSignUp = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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
        final pendingEmail =
            await ref.read(authControllerProvider.notifier).signUpWithEmail(
                  _emailCtrl.text.trim(),
                  _passwordCtrl.text.trim(),
                  _nameCtrl.text.trim(),
                );

        if (pendingEmail != null && mounted) {
          // Email confirmation is still enabled in Supabase —
          // show message and flip to sign-in view.
          setState(() {
            _isLoading = false;
            _error =
                'Check your inbox at $pendingEmail and confirm your email, then sign in below.';
            _isSignUp = false;
          });
          return;
        }
        // Sign-up succeeded and session is live — the router's
        // refreshListenable fires automatically and redirects to /camera.
      } else {
        await ref.read(authControllerProvider.notifier).signInWithEmail(
              _emailCtrl.text.trim(),
              _passwordCtrl.text.trim(),
            );
        // Sign-in succeeded — router redirect handles navigation to /camera.
        // No manual context.go() needed; calling it would race the redirect.
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _friendlyError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('Invalid login')) return 'Wrong email or password';
    if (raw.contains('already registered')) return 'Account already exists — sign in instead';
    if (raw.contains('Password should')) return 'Password must be at least 6 characters';
    return 'Something went wrong. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 64),

              // Brand
              Text(
                'tavera.',
                style: AppTextStyles.displayLarge.copyWith(
                  color: AppColors.accent,
                ),
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

              // Toggle
              Row(
                children: [
                  _TabButton(
                    label: 'Create account',
                    isActive: _isSignUp,
                    onTap: () => setState(() => _isSignUp = true),
                  ),
                  const SizedBox(width: 24),
                  _TabButton(
                    label: 'Sign in',
                    isActive: !_isSignUp,
                    onTap: () => setState(() => _isSignUp = false),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // Fields
              if (_isSignUp) ...[
                _InputField(
                  controller: _nameCtrl,
                  hint: 'Your name',
                  icon: Icons.person_outline_rounded,
                ),
                const SizedBox(height: 12),
              ],
              _InputField(
                controller: _emailCtrl,
                hint: 'Email address',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _InputField(
                controller: _passwordCtrl,
                hint: 'Password',
                icon: Icons.lock_outline_rounded,
                obscureText: true,
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: AppTextStyles.caption.copyWith(
                    color: _error!.contains('Check your inbox')
                        ? AppColors.success
                        : AppColors.danger,
                    height: 1.5,
                  ),
                ),
              ],

              const SizedBox(height: 28),

              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : Text(_isSignUp ? 'Get started' : 'Sign in'),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

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
        style: (isActive ? AppTextStyles.labelLarge : AppTextStyles.bodyMedium)
            .copyWith(
          color: isActive ? AppColors.textPrimary : AppColors.textTertiary,
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
