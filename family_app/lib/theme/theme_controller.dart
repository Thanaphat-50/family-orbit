import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// =======================================================
// โหมดสีของแอป (ตามเครื่อง / สว่าง / มืด)
// เก็บไว้ในเครื่อง เปิดแอปครั้งถัดไปยังเป็นโหมดเดิม
// =======================================================

class ThemeController {
  static const String _key = 'theme_mode';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  static Future<void> load() async {
    try {
      final String? saved = await _storage.read(key: _key);

      mode.value = ThemeMode.values.firstWhere(
        (value) => value.name == saved,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      // อ่านไม่ได้ → ตามเครื่อง
    }
  }

  static Future<void> set(ThemeMode value) async {
    mode.value = value;

    try {
      await _storage.write(key: _key, value: value.name);
    } catch (_) {}
  }
}
