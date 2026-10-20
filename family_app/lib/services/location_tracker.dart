import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'location_service.dart';
import 'settings_service.dart';

// =======================================================
// ส่งตำแหน่งให้ครอบครัว ขณะเปิดแอปอยู่ (ทุกแท็บ)
//
// - ทำงานเมื่อ: เปิดแชร์ตำแหน่ง + ได้รับอนุญาตแล้ว + เปิด GPS
// - ไม่ขอสิทธิ์เอง (หน้าแผนที่/หน้าตั้งค่าเป็นคนขอ)
// - หยุดเมื่อแอปไปอยู่เบื้องหลัง → ไม่ติดตามตอนปิดแอป
// =======================================================

class LocationTracker {
  // ส่งใหม่เมื่อขยับเกิน 25 เมตร และไม่ถี่กว่าทุก 30 วินาที
  static const int distanceFilterMeters = 25;
  static const Duration minSendInterval = Duration(seconds: 30);

  static StreamSubscription<Position>? _subscription;
  static bool _starting = false;

  // ยังต้องการให้ทำงานอยู่ไหม (stop() ระหว่างที่กำลังเริ่มจะได้ไม่เริ่มต่อ)
  static bool _wanted = false;
  static DateTime? _lastSentAt;

  static bool get isRunning => _subscription != null;

  static bool get _sharingOff => SettingsService.locationSharing.value == false;

  // เริ่มส่งตำแหน่ง (เรียกซ้ำได้ ถ้าทำงานอยู่แล้วจะไม่เริ่มซ้ำ)
  // current: ตำแหน่งที่เพิ่งอ่านได้ (เช่น จากหน้าแผนที่) → ส่งอันนี้เลย ไม่ต้องอ่านใหม่
  static Future<void> start({Position? current}) async {
    if (_sharingOff) return;

    if (isRunning || _starting) {
      if (current != null) await _send(current, force: true);
      return;
    }

    _wanted = true;
    _starting = true;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;

      final LocationPermission permission = await Geolocator.checkPermission();

      final bool allowed =
          permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;

      if (!allowed || _sharingOff) return;

      // ส่งตำแหน่งปัจจุบันทันที ไม่ต้องรอขยับ
      // (ส่งก่อนเริ่ม Stream → จุดแรกของ Stream จะถูกข้ามเพราะเพิ่งส่งไป)
      final Position position =
          current ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );

      await _send(position, force: true);

      // ระหว่างรอตำแหน่ง ผู้ใช้อาจปิดแชร์ / แอปไปอยู่เบื้องหลังแล้ว
      if (!_wanted || _sharingOff || isRunning) return;

      _subscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterMeters,
        ),
      ).listen((position) => _send(position), onError: (_) => stop());
    } catch (_) {
      // อ่านตำแหน่งไม่ได้ → ลองใหม่ตอนกลับมาเปิดแอป
    } finally {
      _starting = false;
    }
  }

  static void stop() {
    _wanted = false;
    _subscription?.cancel();
    _subscription = null;
  }

  static Future<void> _send(Position position, {bool force = false}) async {
    if (_sharingOff) return;

    final DateTime now = DateTime.now();

    final DateTime? last = _lastSentAt;

    if (!force && last != null && now.difference(last) < minSendInterval) {
      return;
    }

    _lastSentAt = now;

    try {
      await LocationService.updateLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (_) {
      // Server มีปัญหา → รอบหน้าลองใหม่
    }
  }
}
