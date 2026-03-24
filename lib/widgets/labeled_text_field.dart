import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// Shared labeled text input used across meal editing, manual add, and body
/// stats sheets. Consolidates the identical Container + TextField pattern
/// that was duplicated across food_item_card.dart, review_sheet.dart, and
/// profile_screen.dart.
class LabeledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? suffixText;
  final TextInputType keyboardType;
  final TextAlign textAlign;
  final ValueChanged<String>? onChanged;

  const LabeledTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.suffixText,
    this.keyboardType = TextInputType.text,
    this.textAlign = TextAlign.start,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            textAlign: textAlign,
            style: AppTextStyles.bodyLarge,
            cursorColor: AppColors.accent,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textTertiary),
              suffixText: suffixText,
              suffixStyle: AppTextStyles.caption,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
