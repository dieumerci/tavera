import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class TaveraLoading extends StatelessWidget {
  final double size;
  const TaveraLoading({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(
        color: AppColors.accent,
        strokeWidth: 2,
      ),
    );
  }
}
