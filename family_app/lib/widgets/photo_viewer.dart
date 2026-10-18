import 'package:flutter/material.dart';

// =======================================================
// ดูรูปเต็มจอ
// - ปัดซ้าย-ขวาเพื่อดูรูปถัดไป
// - จีบนิ้ว หรือแตะสองครั้งเพื่อซูม
// =======================================================

Future<void> showPhotoViewer(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: PhotoViewerPage(urls: urls, initialIndex: initialIndex),
        );
      },
    ),
  );
}

class PhotoViewerPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const PhotoViewerPage({super.key, required this.urls, this.initialIndex = 0});

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController pageController = PageController(
    initialPage: widget.initialIndex,
  );

  late int currentIndex = widget.initialIndex;

  // ซูมอยู่ → ล็อกการปัดเปลี่ยนรูป เพื่อให้ลากดูส่วนที่ซูมได้
  bool zoomed = false;

  void onZoomChanged(bool value) {
    if (value != zoomed) {
      setState(() {
        zoomed = value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final int total = widget.urls.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: pageController,
            physics: zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: total,
            onPageChanged: (index) {
              setState(() {
                currentIndex = index;
                zoomed = false;
              });
            },
            itemBuilder: (context, index) {
              return _ZoomablePhoto(
                key: ValueKey('photo-$index'),
                url: widget.urls[index],
                onZoomChanged: onZoomChanged,
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'ปิด',
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.35),
                    ),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const Spacer(),
                  if (total > 1)
                    Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${currentIndex + 1} / $total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    pageController.dispose();

    super.dispose();
  }
}

// =======================================================
// รูปหนึ่งรูปที่ซูมได้
// =======================================================

class _ZoomablePhoto extends StatefulWidget {
  final String url;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomablePhoto({
    super.key,
    required this.url,
    required this.onZoomChanged,
  });

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  static const double doubleTapScale = 2.5;

  final TransformationController controller = TransformationController();

  Offset doubleTapPosition = Offset.zero;

  bool get isZoomed => controller.value.getMaxScaleOnAxis() > 1.01;

  // แตะสองครั้ง: ซูมเข้าตรงจุดที่แตะ / ซูมอยู่แล้วให้กลับขนาดเดิม
  void toggleZoom() {
    if (isZoomed) {
      controller.value = Matrix4.identity();
    } else {
      const double offset = doubleTapScale - 1;

      controller.value =
          Matrix4.diagonal3Values(doubleTapScale, doubleTapScale, 1)
            ..setTranslationRaw(
              -doubleTapPosition.dx * offset,
              -doubleTapPosition.dy * offset,
              0,
            );
    }

    widget.onZoomChanged(isZoomed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) {
        doubleTapPosition = details.localPosition;
      },
      onDoubleTap: toggleZoom,
      child: InteractiveViewer(
        transformationController: controller,
        minScale: 1,
        maxScale: 4,
        onInteractionEnd: (_) {
          widget.onZoomChanged(isZoomed);
        },
        child: Image.network(
          widget.url,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;

            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 48,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'โหลดรูปไม่สำเร็จ',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();

    super.dispose();
  }
}
