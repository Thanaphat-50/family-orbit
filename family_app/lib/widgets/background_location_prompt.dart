import 'package:flutter/material.dart';

import '../services/background_location.dart';
import '../theme/app_theme.dart';

// =======================================================
// เปิด "แชร์ตำแหน่งแม้ไม่ได้เปิดแอป"
// อธิบายให้ชัดก่อนขอสิทธิ์ "ตลอดเวลา" (Google Play กำหนด)
// คืนค่า true เมื่อเปิดสำเร็จ
// =======================================================

Future<bool> enableBackgroundLocation(BuildContext context) async {
  final bool? agreed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        Icons.share_location_rounded,
        color: AppColors.primary,
        size: 36,
      ),
      title: const Text('แชร์ตำแหน่งแม้ไม่ได้เปิดแอป'),
      content: SingleChildScrollView(
        child: Text(
          'ใกล้กันจะเก็บตำแหน่งของคุณและส่งให้สมาชิกในครอบครัวเห็น '
          'แม้ตอนปิดแอปหรือไม่ได้ใช้งานอยู่\n\n'
          '• ครอบครัวรู้ว่าคุณอยู่ที่ไหน และนำทางไปหาได้\n'
          '• ส่งเมื่อคุณขยับ และอย่างน้อยทุก 5 นาที\n'
          '• มีแจ้งเตือน "ใกล้กันกำลังแชร์ตำแหน่ง" ค้างไว้ระหว่างทำงาน\n'
          '• ปิดได้ทุกเมื่อที่ ตั้งค่า\n\n'
          'หน้าถัดไป ให้เลือก "อนุญาตตลอดเวลา"',
          style: TextStyle(color: AppColors.navy, fontSize: 14, height: 1.55),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('ไม่ใช่ตอนนี้'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('ดำเนินการต่อ'),
        ),
      ],
    ),
  );

  if (agreed != true) return false;

  final String? problem = await BackgroundLocation.turnOn();

  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            problem ?? 'เปิดแล้ว ครอบครัวจะเห็นตำแหน่งของคุณแม้ปิดแอป',
          ),
        ),
      );
  }

  return problem == null;
}
