import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

// =======================================================
// วิดีโอบนการ์ดสินค้า (ผู้ขายเลือกหน้าปกเป็นวิดีโอ)
// - เล่นเอง (ปิดเสียง วนซ้ำ) เมื่อเลื่อนหน้าจอมาหยุดที่การ์ด
// - นิ้วแตะ / เมาส์วางบนการ์ด → เล่นทันที
// - เล่นทีละคลิป (การ์ดที่เห็นเต็มที่สุด) ประหยัดเน็ตและแบตเตอรี่
// ระหว่างโหลดและตอนไม่เล่น แสดง placeholder (รูปหน้าปก)
// =======================================================

class AutoplayVideoCover extends StatefulWidget {
  final String videoUrl;
  final Widget placeholder;

  const AutoplayVideoCover({
    super.key,
    required this.videoUrl,
    required this.placeholder,
  });

  @override
  State<AutoplayVideoCover> createState() => _AutoplayVideoCoverState();
}

class _AutoplayVideoCoverState extends State<AutoplayVideoCover> {
  final Key detectorKey = UniqueKey();

  VideoPlayerController? controller;

  // ต้องการให้เล่นอยู่ (ใช้ตอนวิดีโอยังโหลดไม่เสร็จ)
  bool wantsPlay = false;

  bool ready = false;

  @override
  void initState() {
    super.initState();

    // รายงานการมองเห็นถี่กว่าค่าเริ่มต้น → รู้ว่าเลื่อนหยุดเร็วขึ้น
    VisibilityDetectorController.instance.updateInterval =
        _CardVideos.reportInterval;
  }

  Future<void> start() async {
    wantsPlay = true;

    final VideoPlayerController? current = controller;

    if (current != null) {
      if (ready) await current.play();
      return;
    }

    final VideoPlayerController created = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    controller = created;

    try {
      await created.initialize();
    } catch (_) {
      if (controller == created) controller = null;

      await created.dispose();
      return;
    }

    // ระหว่างโหลด การ์ดถูกเลื่อนออกไป / ถูกปิด → ทิ้ง
    if (!mounted || !wantsPlay || controller != created) {
      if (controller == created) controller = null;

      await created.dispose();
      return;
    }

    await created.setVolume(0);
    await created.setLooping(true);
    await created.play();

    if (mounted) setState(() => ready = true);
  }

  // หยุดและคืนหน่วยความจำ (กลับมาเห็นอีกครั้งค่อยโหลดใหม่)
  void stop() {
    wantsPlay = false;

    final VideoPlayerController? current = controller;

    // ยังโหลดไม่เสร็จ → start() จะทิ้งเองเมื่อโหลดเสร็จ
    if (current == null || !current.value.isInitialized) return;

    controller = null;

    if (mounted) setState(() => ready = false);

    current.dispose();
  }

  @override
  void dispose() {
    _CardVideos.remove(this);

    wantsPlay = false;

    final VideoPlayerController? current = controller;

    controller = null;

    if (current != null && current.value.isInitialized) current.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? current = controller;

    return VisibilityDetector(
      key: detectorKey,
      onVisibilityChanged: (info) {
        if (mounted) _CardVideos.report(this, info.visibleFraction);
      },
      child: MouseRegion(
        onEnter: (_) => _CardVideos.hover(this, true),
        onExit: (_) => _CardVideos.hover(this, false),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            if (event.kind == PointerDeviceKind.touch) _CardVideos.touch(this);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.placeholder,
              if (ready && current != null && current.value.isInitialized)
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: current.value.size.width,
                    height: current.value.size.height,
                    child: VideoPlayer(current),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =======================================================
// เลือกว่าการ์ดไหนได้เล่น (ทีละ 1 การ์ดทั้งแอป)
// =======================================================

class _CardVideos {
  static const Duration reportInterval = Duration(milliseconds: 150);

  // ไม่มีรายงานใหม่นานเท่านี้ = เลื่อนหน้าจอหยุดแล้ว
  static const Duration settleDelay = Duration(milliseconds: 450);

  // เห็นการ์ดอย่างน้อยเท่านี้ถึงเล่น / ต่ำกว่านี้หยุด
  static const double playFraction = 0.6;
  static const double stopFraction = 0.3;

  static final Map<_AutoplayVideoCoverState, double> visible = {};

  static _AutoplayVideoCoverState? active;
  static _AutoplayVideoCoverState? hovered;
  static Timer? settleTimer;

  static void report(_AutoplayVideoCoverState card, double fraction) {
    if (fraction <= 0.01) {
      visible.remove(card);

      if (hovered == card) hovered = null;
    } else {
      visible[card] = fraction;
    }

    if (active == card && fraction < stopFraction) {
      card.stop();
      active = null;
    }

    // รายงานใหม่ = ยังเลื่อนอยู่ → รอให้หยุดก่อนค่อยเลือก
    settleTimer?.cancel();
    settleTimer = Timer(settleDelay, pick);
  }

  static void pick() {
    activate(hovered ?? best());
  }

  // การ์ดที่เห็นเต็มที่สุด (เท่ากัน → เล่นการ์ดเดิมต่อ / การ์ดที่อยู่ก่อน)
  static _AutoplayVideoCoverState? best() {
    _AutoplayVideoCoverState? result;
    double top = playFraction;

    final _AutoplayVideoCoverState? current = active;

    if (current != null && (visible[current] ?? 0) >= playFraction) {
      result = current;
      top = visible[current]!;
    }

    visible.forEach((card, fraction) {
      if (fraction > top + 0.05 || (result == null && fraction >= top)) {
        result = card;
        top = fraction;
      }
    });

    return result;
  }

  static void activate(_AutoplayVideoCoverState? card) {
    if (card != active) {
      active?.stop();
      active = card;
    }

    card?.start();
  }

  // นิ้วแตะการ์ด → เล่นการ์ดนี้ทันที
  static void touch(_AutoplayVideoCoverState card) {
    settleTimer?.cancel();

    activate(card);
  }

  // เมาส์วางบนการ์ด → เล่นจนกว่าเมาส์ออก
  static void hover(_AutoplayVideoCoverState card, bool inside) {
    if (inside) {
      hovered = card;
      activate(card);
    } else if (hovered == card) {
      hovered = null;
      pick();
    }
  }

  static void remove(_AutoplayVideoCoverState card) {
    visible.remove(card);

    if (active == card) active = null;
    if (hovered == card) hovered = null;
  }
}
