import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'feed_page.dart';

// =======================================================
// หน้าแฮชแท็ก: โพสต์ในชุมชนที่มี #แท็กนี้ (ล่าสุดก่อน)
// =======================================================

class HashtagPage extends StatelessWidget {
  final String tag;

  const HashtagPage({super.key, required this.tag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('#$tag')),
      body: FeedPage(
        scope: FeedScope.community,
        hashtag: tag,
        header: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.tag_rounded, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#$tag',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'โพสต์และวิดีโอในชุมชนที่ใส่แท็กนี้',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5),
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
