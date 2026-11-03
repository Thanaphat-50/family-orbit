import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// =======================================================
// แชร์โพสต์ (ฟีด / หน้าวิดีโอ ใช้แบบเดียวกัน)
// - showShareChannelSheet: เลือก external / community / family
// - askShareNote: ข้อความเพิ่มเติมตอนแชร์ในแอป
// =======================================================

// สีฝั่งชุมชน (โหมดมืดใช้โทนสว่างกว่าให้อ่านง่าย) ตรงกับ FeedPage
Color get _communityColor =>
    AppColors.isDark ? const Color(0xFF2A9CC4) : const Color(0xFF0B7FA6);

// ตรงกับ Laravel (content max:5000)
const int _maxNoteLength = 5000;

// คืน channel ที่เลือก / null = ปิดไปเฉย ๆ
Future<String?> showShareChannelSheet(BuildContext context) {
  Widget option(
    BuildContext sheetContext, {
    required String channel,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return ListTile(
      onTap: () => Navigator.of(sheetContext).pop(channel),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: AppColors.navy,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: AppColors.muted, fontSize: 12),
      ),
    );
  }

  FocusManager.instance.primaryFocus?.unfocus();

  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'แชร์โพสต์',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            option(
              sheetContext,
              channel: 'external',
              icon: Icons.ios_share_rounded,
              title: 'ส่งต่อไปแอปอื่น',
              subtitle: 'LINE, Facebook, Messenger และอื่น ๆ',
              color: AppColors.success,
            ),
            option(
              sheetContext,
              channel: 'community',
              icon: Icons.repeat_rounded,
              title: 'แชร์ในชุมชน',
              subtitle: 'โพสต์ซ้ำในฟีดชุมชน เขียนข้อความเพิ่มได้',
              color: _communityColor,
            ),
            option(
              sheetContext,
              channel: 'family',
              icon: Icons.groups_rounded,
              title: 'ส่งให้กลุ่ม',
              subtitle: 'แชร์เข้าไปในหน้ากลุ่มสมาชิก',
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    ),
  );
}

// ข้อความเพิ่มเติมตอนแชร์ในแอป (null = ยกเลิก)
Future<String?> askShareNote(BuildContext context, String channel) async {
  final TextEditingController controller = TextEditingController();

  final String? note = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(channel == 'community' ? 'แชร์ในชุมชน' : 'ส่งให้กลุ่ม'),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        maxLength: _maxNoteLength,
        decoration: const InputDecoration(
          hintText: 'เขียนอะไรสักหน่อย (ไม่บังคับ)',
          counterText: '',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('แชร์'),
        ),
      ],
    ),
  );

  // รอหน้าต่างปิดเสร็จก่อนค่อยทิ้ง Controller
  Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);

  return note;
}
