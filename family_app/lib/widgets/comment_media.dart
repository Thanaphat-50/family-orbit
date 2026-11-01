import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import '../pages/video_player_page.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';
import 'photo_viewer.dart';

// =======================================================
// ไฟล์แนบในความคิดเห็น (รูป / GIF / วิดีโอ)
// - CommentMediaThumb: แสดงย่อ แตะเพื่อดูเต็มจอ
// - pickCommentMedia: เลือกรูป / GIF / วิดีโอ จากเครื่อง
// - commentMediaFromKeyboard: GIF / สติกเกอร์ที่ส่งมาจากคีย์บอร์ด (เช่น Gboard)
// - CommentMediaPreview: ตัวอย่างไฟล์ที่เลือกไว้ก่อนส่ง (กด × เพื่อเอาออก)
// ขนาดตรงกับ Laravel (CommentController): รูป/GIF ≤ 10 MB วิดีโอ ≤ 20 MB
// =======================================================

const int commentImageMaxBytes = 10 * 1024 * 1024;
const int commentVideoMaxBytes = 20 * 1024 * 1024;
const int commentVideoMaxSeconds = 30;

// ชนิดไฟล์ที่ให้คีย์บอร์ดส่งมาได้
const List<String> commentKeyboardMimeTypes = [
  'image/gif',
  'image/png',
  'image/jpeg',
  'image/webp',
];

// =======================================================
// แสดงย่อในความคิดเห็น
// =======================================================

class CommentMediaThumb extends StatelessWidget {
  final Map<String, dynamic> media;

  // ด้านยาวสุดของรูปย่อ
  final double maxSize;

  const CommentMediaThumb({super.key, required this.media, this.maxSize = 120});

  String get type => media['type']?.toString() ?? 'image';

  // ขนาดย่อตามสัดส่วนจริง (ไม่รู้ขนาด = สี่เหลี่ยมจัตุรัส)
  Size get boxSize {
    final double? width = (media['width'] as num?)?.toDouble();

    final double? height = (media['height'] as num?)?.toDouble();

    if (width == null || height == null || width <= 0 || height <= 0) {
      return Size.square(maxSize * 0.8);
    }

    final double ratio = (width / height).clamp(0.6, 1.8);

    return ratio >= 1
        ? Size(maxSize, maxSize / ratio)
        : Size(maxSize * ratio, maxSize);
  }

  void open(BuildContext context) {
    final String? url = media['url']?.toString();

    if (url == null || url.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => type == 'video'
            ? VideoPlayerPage(url: url)
            : PhotoViewerPage(urls: [url]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool video = type == 'video';

    final String? imageUrl = (video ? media['thumbnail_url'] : media['url'])
        ?.toString();

    final Size size = boxSize;

    return GestureDetector(
      onTap: () => open(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: size.width,
          height: size.height,
          color: video ? Colors.black : AppColors.fill,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Icon(Icons.broken_image_outlined, color: AppColors.muted),
                ),
              if (video)
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              if (type == 'gif') const _Badge('GIF'),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;

  const _Badge(this.label);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 6,
      bottom: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// =======================================================
// เลือกไฟล์แนบ
// =======================================================

String? _mimeOfPath(String path) {
  final String lower = path.toLowerCase();

  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.3gp')) return 'video/3gpp';

  return null;
}

// ขนาดรูป (ใช้จัดสัดส่วนรูปย่อ) ไม่สำเร็จ = null
Future<Size?> _imageSize(String path) async {
  try {
    final Uint8List bytes = await File(path).readAsBytes();

    final image = await decodeImageFromList(bytes);

    final Size size = Size(image.width.toDouble(), image.height.toDouble());

    image.dispose();

    return size;
  } catch (_) {
    return null;
  }
}

Future<CommentMediaFile?> _imageFile(BuildContext context, String path) async {
  final String? mime = _mimeOfPath(path);

  if (mime == null || !mime.startsWith('image/')) {
    _toast(context, 'รองรับเฉพาะรูป JPG, PNG, WEBP หรือ GIF');
    return null;
  }

  if (await File(path).length() > commentImageMaxBytes) {
    if (context.mounted) _toast(context, 'รูปหรือ GIF ต้องมีขนาดไม่เกิน 10 MB');
    return null;
  }

  final Size? size = await _imageSize(path);

  return CommentMediaFile(
    path: path,
    type: mime == 'image/gif' ? 'gif' : 'image',
    mimeType: mime,
    width: size?.width.round(),
    height: size?.height.round(),
  );
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

// แสดงเมนู รูปภาพ / GIF / วิดีโอ แล้วคืนไฟล์ที่พร้อมส่ง (null = ยกเลิก/ใช้ไม่ได้)
// onBusy: แจ้งตอนกำลังเตรียมวิดีโอ (บีบอัด) ให้หน้าที่เรียกแสดงสถานะ
Future<CommentMediaFile?> pickCommentMedia(
  BuildContext context, {
  ValueChanged<bool>? onBusy,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();

  final String? kind = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.image_outlined, color: AppColors.primary),
            title: const Text('รูปภาพ'),
            onTap: () => Navigator.of(sheetContext).pop('image'),
          ),
          ListTile(
            leading: Icon(Icons.gif_box_outlined, color: AppColors.primary),
            title: const Text('GIF'),
            subtitle: const Text(
              'เลือกจากเครื่อง หรือกดปุ่ม GIF บนคีย์บอร์ดตอนพิมพ์ก็ได้',
            ),
            onTap: () => Navigator.of(sheetContext).pop('gif'),
          ),
          ListTile(
            leading: Icon(Icons.videocam_outlined, color: AppColors.primary),
            title: const Text('วิดีโอ'),
            subtitle: const Text('ยาวไม่เกิน $commentVideoMaxSeconds วินาที'),
            onTap: () => Navigator.of(sheetContext).pop('video'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (kind == null || !context.mounted) return null;

  final ImagePicker picker = ImagePicker();

  try {
    switch (kind) {
      case 'image':
        // ย่อรูปให้เล็กลงก่อนส่ง
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 1600,
        );

        if (image == null || !context.mounted) return null;

        return await _imageFile(context, image.path);

      case 'gif':
        // ไม่ย่อ (ย่อแล้ว GIF จะไม่ขยับ)
        final XFile? gif = await picker.pickImage(source: ImageSource.gallery);

        if (gif == null || !context.mounted) return null;

        return await _imageFile(context, gif.path);

      default:
        return await _videoFile(context, picker, onBusy);
    }
  } catch (_) {
    if (context.mounted) _toast(context, 'เลือกไฟล์ไม่สำเร็จ กรุณาลองอีกครั้ง');

    return null;
  }
}

Future<CommentMediaFile?> _videoFile(
  BuildContext context,
  ImagePicker picker,
  ValueChanged<bool>? onBusy,
) async {
  final XFile? file = await picker.pickVideo(
    source: ImageSource.gallery,
    maxDuration: const Duration(seconds: commentVideoMaxSeconds),
  );

  if (file == null || !context.mounted) return null;

  onBusy?.call(true);

  try {
    final MediaInfo info = await VideoCompress.getMediaInfo(file.path);

    if ((info.duration ?? 0) / 1000 > commentVideoMaxSeconds + 1) {
      if (context.mounted) {
        _toast(context, 'วิดีโอต้องยาวไม่เกิน $commentVideoMaxSeconds วินาที');
      }
      return null;
    }

    String path = file.path;

    // ไฟล์ใหญ่ → บีบอัดให้เล็กลงก่อนส่ง
    if (await File(path).length() > 8 * 1024 * 1024) {
      try {
        final MediaInfo? compressed = await VideoCompress.compressVideo(
          path,
          quality: VideoQuality.MediumQuality,
          includeAudio: true,
        ).timeout(const Duration(minutes: 2));

        path = compressed?.path ?? path;
      } catch (_) {
        await VideoCompress.cancelCompression();
      }
    }

    if (await File(path).length() > commentVideoMaxBytes) {
      if (context.mounted) {
        _toast(context, 'วิดีโอใหญ่เกิน 20 MB กรุณาเลือกวิดีโอที่สั้นลง');
      }
      return null;
    }

    File? thumbnail;

    try {
      thumbnail = await VideoCompress.getFileThumbnail(file.path, quality: 70);
    } catch (_) {
      // ไม่มีรูปตัวอย่างก็ส่งได้
    }

    return CommentMediaFile(
      path: path,
      type: 'video',
      mimeType: _mimeOfPath(path) ?? 'video/mp4',
      thumbnailPath: thumbnail?.path,
      // video_compress หมุนขนาดตามการถ่าย (แนวตั้ง/แนวนอน) ให้แล้ว
      width: info.width,
      height: info.height,
    );
  } finally {
    onBusy?.call(false);
  }
}

// GIF / สติกเกอร์จากคีย์บอร์ด → เก็บเป็นไฟล์ชั่วคราวเพื่อส่ง
Future<CommentMediaFile?> commentMediaFromKeyboard(
  BuildContext context,
  KeyboardInsertedContent content,
) async {
  final Uint8List? bytes = content.data;

  final String mime = content.mimeType;

  if (bytes == null || !commentKeyboardMimeTypes.contains(mime)) return null;

  if (bytes.length > commentImageMaxBytes) {
    _toast(context, 'รูปหรือ GIF ต้องมีขนาดไม่เกิน 10 MB');
    return null;
  }

  final String extension = mime.split('/').last == 'jpeg'
      ? 'jpg'
      : mime.split('/').last;

  final Directory folder = await Directory.systemTemp.createTemp('comment_');

  final File file = File('${folder.path}/keyboard.$extension');

  await file.writeAsBytes(bytes);

  if (!context.mounted) return null;

  return _imageFile(context, file.path);
}

// =======================================================
// ตัวอย่างไฟล์ที่เลือกไว้ (เหนือช่องพิมพ์)
// =======================================================

class CommentMediaPreview extends StatelessWidget {
  final CommentMediaFile media;

  final VoidCallback onRemove;

  const CommentMediaPreview({
    super.key,
    required this.media,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final bool video = media.type == 'video';

    final String? imagePath = video ? media.thumbnailPath : media.path;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 72,
            height: 72,
            color: video ? Colors.black : AppColors.fill,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imagePath != null)
                  Image.file(
                    File(imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.muted,
                    ),
                  ),
                if (video)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                if (media.type == 'gif') const _Badge('GIF'),
              ],
            ),
          ),
        ),
        Positioned(
          right: -8,
          top: -8,
          child: Material(
            color: AppColors.navy,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 15, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
