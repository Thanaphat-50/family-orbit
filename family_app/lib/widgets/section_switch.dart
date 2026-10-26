import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// =======================================================
// สวิตช์สลับหน้าย่อย
// เช่น หน้าหลัก: ชุมชน | ตลาด
//      ครอบครัว: โพสต์ | สมาชิก
// =======================================================

class SectionOption<T> {
  final T value;
  final IconData icon;
  final String label;

  const SectionOption({
    required this.value,
    required this.icon,
    required this.label,
  });
}

class SectionSwitch<T> extends StatelessWidget {
  final T value;
  final List<SectionOption<T>> options;
  final ValueChanged<T> onChanged;

  const SectionSwitch({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [
          for (final option in options)
            ButtonSegment<T>(
              value: option.value,
              icon: Icon(option.icon, size: 18),
              label: Text(option.label),
            ),
        ],
        selected: {value},
        onSelectionChanged: (selection) {
          onChanged(selection.first);
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.muted,
          selectedBackgroundColor: AppColors.primary,
          selectedForegroundColor: Colors.white,
          side: BorderSide(color: AppColors.border),
          minimumSize: const Size(0, 46),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
