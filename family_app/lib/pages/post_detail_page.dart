import 'package:flutter/material.dart';

import 'feed_page.dart';

// =======================================================
// โพสต์เดียว (เปิดจากการแจ้งเตือน)
// ใช้การ์ดโพสต์เดียวกับฟีด: ถูกใจ ความคิดเห็น รายงาน ลบ
// =======================================================

class PostDetailPage extends StatelessWidget {
  final int postId;

  const PostDetailPage({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('โพสต์')),
      body: FeedPage(
        // scope จริงใช้ตามโพสต์ที่โหลดมา (ครอบครัว/ชุมชน)
        scope: FeedScope.family,
        postId: postId,
      ),
    );
  }
}
