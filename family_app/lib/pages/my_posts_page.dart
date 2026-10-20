import 'package:flutter/material.dart';

import 'feed_page.dart';

// =======================================================
// โพสต์ของฉัน (ครอบครัว + ชุมชน)
// ใช้การ์ดโพสต์เดียวกับฟีด: ถูกใจ ความคิดเห็น ลบ
// โพสต์ชุมชนที่ถูกซ่อนจะมีป้ายบอก
// =======================================================

class MyPostsPage extends StatelessWidget {
  const MyPostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('โพสต์ของฉัน')),
      body: const FeedPage(scope: FeedScope.mine),
    );
  }
}
