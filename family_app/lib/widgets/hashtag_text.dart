import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../pages/hashtag_page.dart';
import '../theme/app_theme.dart';

// =======================================================
// ข้อความที่มี #แฮชแท็ก: แท็กเป็นสี และกดเปิดหน้าแฮชแท็กได้
// รูปแบบตรงกับ Laravel (Hashtag::PATTERN)
// # ที่อยู่ต้นข้อความหรือหลังช่องว่าง ตามด้วยตัวอักษร (รวมสระ/วรรณยุกต์ไทย) ตัวเลข หรือ _
// =======================================================

final RegExp hashtagPattern = RegExp(
  r'(?<!\S)#([\p{L}\p{M}\p{N}_]+)',
  unicode: true,
);

// กำลังพิมพ์แท็กอยู่ท้ายข้อความ เช่น "วันนี้ #ทำอา"
final RegExp typingHashtagPattern = RegExp(
  r'(?<!\S)#([\p{L}\p{M}\p{N}_]*)$',
  unicode: true,
);

const int hashtagMaxLength = 50;

// แท็กที่ระบบนับ (ไม่ยาวเกิน และไม่ใช่ตัวเลขล้วน เช่น #1)
bool isCountedHashtag(String tag) =>
    tag.length <= hashtagMaxLength && !RegExp(r'^\d+$').hasMatch(tag);

void openHashtagPage(BuildContext context, String tag) {
  FocusManager.instance.primaryFocus?.unfocus();

  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => HashtagPage(tag: tag)));
}

class HashtagText extends StatefulWidget {
  final String text;

  final TextStyle? style;

  // สีของแท็ก (null = สีหลักของแอป)
  final Color? tagColor;

  final int? maxLines;

  final TextOverflow? overflow;

  // กดแท็ก (null = เปิดหน้าแฮชแท็ก)
  final ValueChanged<String>? onTagTap;

  const HashtagText(
    this.text, {
    super.key,
    this.style,
    this.tagColor,
    this.maxLines,
    this.overflow,
    this.onTagTap,
  });

  @override
  State<HashtagText> createState() => _HashtagTextState();
}

class _HashtagTextState extends State<HashtagText> {
  final List<TapGestureRecognizer> recognizers = [];

  void clearRecognizers() {
    for (final recognizer in recognizers) {
      recognizer.dispose();
    }

    recognizers.clear();
  }

  void openTag(String tag) {
    final ValueChanged<String>? onTagTap = widget.onTagTap;

    if (onTagTap != null) {
      onTagTap(tag);
    } else {
      openHashtagPage(context, tag);
    }
  }

  @override
  Widget build(BuildContext context) {
    clearRecognizers();

    final String text = widget.text;

    final List<InlineSpan> spans = [];

    int last = 0;

    for (final RegExpMatch match in hashtagPattern.allMatches(text)) {
      final String tag = match.group(1)!;

      if (!isCountedHashtag(tag)) continue;

      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }

      final TapGestureRecognizer recognizer = TapGestureRecognizer()
        ..onTap = () => openTag(tag);

      recognizers.add(recognizer);

      spans.add(
        TextSpan(
          text: match.group(0),
          recognizer: recognizer,
          style: TextStyle(
            color: widget.tagColor ?? AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

      last = match.end;
    }

    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));

    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }

  @override
  void dispose() {
    clearRecognizers();

    super.dispose();
  }
}
