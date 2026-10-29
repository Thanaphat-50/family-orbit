import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// =======================================================
// ดูวิดีโอในโพสต์ (เต็มจอ พื้นดำ)
// แตะจอ = เล่น/หยุด, ลากแถบด้านล่าง = เลื่อนเวลา
// =======================================================

class VideoPlayerPage extends StatefulWidget {
  final String url;

  const VideoPlayerPage({super.key, required this.url});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final VideoPlayerController controller;

  bool failed = false;

  @override
  void initState() {
    super.initState();

    controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..addListener(() {
        if (mounted) setState(() {});
      });

    controller
        .initialize()
        .then((_) {
          if (mounted) controller.play();
        })
        .catchError((_) {
          if (mounted) setState(() => failed = true);
        });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void togglePlay() {
    if (!controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      // ดูจบแล้วกดอีกครั้ง → เริ่มใหม่
      if (controller.value.position >= controller.value.duration) {
        controller.seekTo(Duration.zero);
      }

      controller.play();
    }
  }

  static String formatTime(Duration value) {
    final int minutes = value.inMinutes;

    final String seconds = (value.inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerValue value = controller.value;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: failed
            ? const Center(
                child: Text(
                  'เปิดวิดีโอไม่ได้ กรุณาลองใหม่',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : !value.isInitialized
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: togglePlay,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Center(
                            child: AspectRatio(
                              aspectRatio: value.aspectRatio,
                              child: VideoPlayer(controller),
                            ),
                          ),
                          if (!value.isPlaying)
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                          if (value.isBuffering)
                            const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        Text(
                          formatTime(value.position),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: VideoProgressIndicator(
                            controller,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            colors: const VideoProgressColors(
                              playedColor: Colors.white,
                              bufferedColor: Colors.white38,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          formatTime(value.duration),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
