import 'package:url_launcher/url_launcher.dart';

import 'api_config.dart';

// =======================================================
// ข้อมูลแอป: ชื่อ และลิงก์หน้านโยบาย
// เปลี่ยนชื่อแอปที่นี่ที่เดียว (ยกเว้นชื่อใต้ไอคอนใน
// android/app/src/main/AndroidManifest.xml → android:label)
// =======================================================

class AppInfo {
  static const String name = 'ใกล้กัน';

  // หน้าเว็บนโยบายบน Laravel (ลิงก์เดียวกับที่ใส่ใน Google Play)
  static const String privacyUrl = '${ApiConfig.serverUrl}/privacy';
  static const String termsUrl = '${ApiConfig.serverUrl}/terms';
  static const String childSafetyUrl = '${ApiConfig.serverUrl}/child-safety';

  // เปิดหน้าเว็บในเบราว์เซอร์ คืนค่า false ถ้าเปิดไม่ได้
  static Future<bool> openUrl(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
