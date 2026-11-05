import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_theme.dart';

// =======================================================
// QR พร้อมเพย์ (ช่องแนะนำ / คำสั่งซื้อ)
// =======================================================

class PromptPayQrImage extends StatelessWidget {
  final String payload;
  final double size;

  const PromptPayQrImage({super.key, required this.payload, this.size = 220});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: QrImageView(
        data: payload,
        size: size,
        backgroundColor: Colors.white,
        semanticsLabel: 'QR พร้อมเพย์',
      ),
    );
  }
}

// บันทึก/แชร์รูป QR → เปิดแอปธนาคารแล้วสแกนจากรูปในเครื่อง
// คืนข้อความ error (null = สำเร็จ)
Future<String?> sharePromptPayQr({
  required String payload,
  required String amount,
  required String fileTag,
}) async {
  try {
    final painter = QrPainter(
      data: payload,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );

    final image = await painter.toImage(720);

    // พื้นขาวรอบ QR (แอปธนาคารอ่านง่ายขึ้น)
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const double size = 800;

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, size, size),
      Paint()..color = Colors.white,
    );
    canvas.drawImage(image, const Offset(40, 40), Paint());

    final picture = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);

    if (bytes == null) throw Exception('สร้างรูป QR ไม่สำเร็จ');

    final File file = File(
      '${Directory.systemTemp.path}/promptpay_$fileTag.png',
    );

    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: 'QR พร้อมเพย์ ยอด $amount บาท',
      ),
    );

    return null;
  } catch (e) {
    return 'บันทึก QR ไม่สำเร็จ: $e';
  }
}
