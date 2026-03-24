import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Standard drag-handle bar placed at the top of every bottom sheet.
/// Width 40, height 4, rounded, AppColors.border fill.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
