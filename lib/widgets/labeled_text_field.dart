import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../services/haptic_service.dart';

/// Shared labeled text input used across meal editing, manual add, and body
/// stats sheets. Consolidates the identical Container + TextField pattern
/// that was duplicated across food_item_card.dart, review_sheet.dart, and
/// profile_screen.dart. Fires a light haptic on focus.
class LabeledTextField extends StatefulWidget {
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
  State<LabeledTextField> createState() => _LabeledTextFieldState();
}

class _LabeledTextFieldState extends State<LabeledTextField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) HapticService.selection();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AppTextStyles.caption),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            keyboardType: widget.keyboardType,
            textAlign: widget.textAlign,
            style: AppTextStyles.bodyLarge,
            cursorColor: AppColors.accent,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textTertiary),
              suffixText: widget.suffixText,
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
